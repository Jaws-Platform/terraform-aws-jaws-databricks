"""Export Databricks billing system tables to S3, as whole-billing-period snapshots.

Runs daily as a spark_python_task on serverless jobs compute. Each run writes,
under --prefix in --bucket, with one run stamp for all of them:

  table=list_prices/run=<YYYYMMDDTHHMMSSZ>/part-0.parquet                    system.billing.list_prices
  table=workspaces/run=<…>/part-0.parquet   (--include-workspaces)           system.access.workspaces_latest
  table=usage/billing_period=YYYY-MM/run=<…>/part-0.parquet  (each period)   system.billing.usage

--periods is `recent` (the previous and the current UTC month), `all` (every
month in system.billing.usage: the backfill) or a comma list of YYYY-MM.

Every object is written with an explicit Arrow schema and sorted rows, so the
same content gives the same bytes (and ETag), and a field Databricks adds later
never changes the output. S3 is reached through a Unity Catalog service
credential, so the job holds no AWS keys.
"""

import io
import re
import sys
from collections.abc import Callable, Mapping, Sequence
from datetime import UTC, date, datetime

import pyarrow as pa
import pyarrow.parquet as pq

_TS = pa.timestamp("us", tz="UTC")
_DECIMAL = pa.decimal128(38, 18)
_MAP = pa.map_(pa.string(), pa.string())

_USAGE_METADATA = [
    "cluster_id", "job_id", "warehouse_id", "instance_pool_id", "node_type", "job_run_id", "notebook_id",
    "dlt_pipeline_id", "endpoint_name", "endpoint_id", "app_id", "app_name", "database_instance_id", "job_name",
    "run_name", "budget_policy_id", "usage_policy_id",
]

USAGE_SCHEMA = pa.schema([
    ("record_id", pa.string()),
    ("account_id", pa.string()),
    ("workspace_id", pa.string()),
    ("sku_name", pa.string()),
    ("cloud", pa.string()),
    ("usage_start_time", _TS),
    ("usage_end_time", _TS),
    ("usage_date", pa.date32()),
    ("custom_tags", _MAP),
    ("usage_unit", pa.string()),
    ("usage_quantity", _DECIMAL),
    ("usage_metadata", pa.struct([(name, pa.string()) for name in _USAGE_METADATA])),
    ("identity_metadata", pa.struct([("run_as", pa.string()), ("owned_by", pa.string()), ("created_by", pa.string())])),
    ("record_type", pa.string()),
    ("ingestion_date", pa.date32()),
    ("billing_origin_product", pa.string()),
    ("product_features", pa.struct([
        ("is_serverless", pa.bool_()), ("is_photon", pa.bool_()), ("jobs_tier", pa.string()),
        ("sql_tier", pa.string()), ("serving_type", pa.string()), ("performance_target", pa.string()),
    ])),
    ("usage_type", pa.string()),
])

PRICES_SCHEMA = pa.schema([
    ("price_start_time", _TS),
    ("price_end_time", _TS),
    ("account_id", pa.string()),
    ("sku_name", pa.string()),
    ("cloud", pa.string()),
    ("currency_code", pa.string()),
    ("usage_unit", pa.string()),
    ("pricing", pa.struct([
        ("default", _DECIMAL),
        ("promotional", pa.struct([("default", _DECIMAL)])),
        ("effective_list", pa.struct([("default", _DECIMAL)])),
    ])),
])

WORKSPACES_SCHEMA = pa.schema([
    ("workspace_id", pa.string()),
    ("workspace_name", pa.string()),
    ("workspace_url", pa.string()),
    ("status", pa.string()),
])

SORT_KEYS: dict[str, tuple[str, ...]] = {
    "usage": ("record_id",),
    "list_prices": ("sku_name", "cloud", "price_start_time"),
    "workspaces": ("workspace_id",),
}

_MONTH = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")


def _shift(year: int, month: int, by: int) -> tuple[int, int]:
    index = year * 12 + (month - 1) + by
    return index // 12, index % 12 + 1


def periods_to_export(spec: str, today: date, available: Callable[[], list[str]]) -> list[str]:
    """The billing periods (YYYY-MM) a --periods value names, sorted; ValueError if it names none."""
    spec = (spec or "").strip()
    if spec == "recent":
        previous = _shift(today.year, today.month, -1)
        return [f"{previous[0]:04d}-{previous[1]:02d}", f"{today.year:04d}-{today.month:02d}"]
    if spec == "all":
        return sorted(set(available()))
    months = [part.strip() for part in spec.split(",")]
    if not months or not all(_MONTH.match(month) for month in months):
        raise ValueError(f"--periods must be recent, all or a comma list of YYYY-MM months, not {spec!r}")
    return sorted(set(months))


def month_bounds(period: str) -> tuple[str, str]:
    """The period's first day and the next month's first day, as ISO dates."""
    year, month = int(period[:4]), int(period[5:])
    following = _shift(year, month, 1)
    return f"{year:04d}-{month:02d}-01", f"{following[0]:04d}-{following[1]:02d}-01"


def run_stamp(now: datetime) -> str:
    return now.astimezone(UTC).strftime("%Y%m%dT%H%M%SZ")


def usage_key(prefix: str, period: str, run: str) -> str:
    return f"{prefix}/table=usage/billing_period={period}/run={run}/part-0.parquet"


def table_key(prefix: str, table: str, run: str) -> str:
    return f"{prefix}/table={table}/run={run}/part-0.parquet"


def _project(value, kind: pa.DataType):
    """The value reduced to what the Arrow type holds: unknown struct fields dropped, maps as pairs."""
    if value is None:
        return None
    if pa.types.is_struct(kind):
        return {kind.field(i).name: _project(value.get(kind.field(i).name), kind.field(i).type)
                for i in range(kind.num_fields)}
    if pa.types.is_map(kind):
        items = value.items() if isinstance(value, Mapping) else value
        return sorted((str(k), None if v is None else str(v)) for k, v in items)
    return value


def _sort_key(row: Mapping, keys: Sequence[str]) -> tuple:
    return tuple((row.get(key) is not None, str(row.get(key))) for key in keys)


def to_parquet(rows: list[dict], schema: pa.Schema, sort_keys: Sequence[str]) -> bytes:
    """Rows as Parquet in exactly this schema, sorted, so the same rows always give the same bytes."""
    projected = [{field.name: _project(row.get(field.name), field.type) for field in schema} for row in rows]
    projected.sort(key=lambda row: _sort_key(row, sort_keys))
    table = pa.Table.from_pylist(projected, schema=schema)
    sink = io.BytesIO()
    pq.write_table(table, sink, compression="snappy", write_statistics=False)
    return sink.getvalue()


USAGE_QUERY = "SELECT * FROM system.billing.usage WHERE usage_date >= DATE'{start}' AND usage_date < DATE'{end}'"
PRICES_QUERY = "SELECT * FROM system.billing.list_prices"
WORKSPACES_QUERY = "SELECT workspace_id, workspace_name, workspace_url, status FROM system.access.workspaces_latest"
PERIODS_QUERY = "SELECT DISTINCT date_format(usage_date, 'yyyy-MM') AS period FROM system.billing.usage"


def export(
    query: Callable[[str], list[dict]],
    put: Callable[[str, bytes], None],
    *,
    prefix: str,
    periods: str,
    include_workspaces: bool,
    now: datetime,
) -> list[str]:
    """Write one run's snapshots and return their keys: prices, workspaces (if included), then each period."""
    chosen = periods_to_export(periods, now.astimezone(UTC).date(),
                               lambda: [row["period"] for row in query(PERIODS_QUERY)])
    run = run_stamp(now)
    written = []

    def write(key: str, rows: list[dict], schema: pa.Schema, table: str) -> None:
        put(key, to_parquet(rows, schema, SORT_KEYS[table]))
        written.append(key)

    write(table_key(prefix, "list_prices", run), query(PRICES_QUERY), PRICES_SCHEMA, "list_prices")
    if include_workspaces:
        write(table_key(prefix, "workspaces", run), query(WORKSPACES_QUERY), WORKSPACES_SCHEMA, "workspaces")
    for period in chosen:
        start, end = month_bounds(period)
        write(usage_key(prefix, period, run), query(USAGE_QUERY.format(start=start, end=end)), USAGE_SCHEMA, "usage")
    return written


def _arguments(argv: list[str]) -> dict[str, str]:
    import argparse

    parser = argparse.ArgumentParser(description="Export Databricks billing system tables to S3.")
    for name in ("--bucket", "--prefix", "--credential", "--region", "--periods"):
        parser.add_argument(name, required=True)
    parser.add_argument("--include-workspaces", choices=["true", "false"], default="false")
    return vars(parser.parse_args(argv))


def main(argv: list[str]) -> None:
    # Only on Databricks: the tests never import these.
    import boto3
    from databricks.sdk.runtime import dbutils
    from pyspark.sql import SparkSession

    args = _arguments(argv)
    spark = SparkSession.builder.getOrCreate()
    # Times are collected as naive datetimes in the session time zone; written as UTC.
    spark.conf.set("spark.sql.session.timeZone", "UTC")

    def query(sql: str) -> list[dict]:
        return [row.asDict(recursive=True) for row in spark.sql(sql).collect()]

    session = boto3.Session(
        botocore_session=dbutils.credentials.getServiceCredentialsProvider(args["credential"]),
        region_name=args["region"],
    )
    client = session.client("s3")

    def put(key: str, body: bytes) -> None:
        client.put_object(Bucket=args["bucket"], Key=key, Body=body, ContentType="application/vnd.apache.parquet")
        print(f"wrote s3://{args['bucket']}/{key} ({len(body)} bytes)")

    keys = export(query, put, prefix=args["prefix"], periods=args["periods"],
                  include_workspaces=args["include_workspaces"] == "true", now=datetime.now(UTC))
    print(f"exported {len(keys)} objects")


if __name__ == "__main__":
    main(sys.argv[1:])
