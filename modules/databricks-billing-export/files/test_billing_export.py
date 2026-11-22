"""Unit tests for billing_export.py, the Databricks billing export job.

Run: uv run --no-project --python 3.13 --with-requirements files/requirements-test.txt \
       python -m unittest discover -s files -p 'test_*.py'
"""

import importlib.util
import io
import unittest
from datetime import UTC, date, datetime
from decimal import Decimal
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq

_HERE = Path(__file__).resolve().parent
_SPEC = importlib.util.spec_from_file_location("billing_export", _HERE / "billing_export.py")
assert _SPEC and _SPEC.loader
export = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(export)


def usage_row(**overrides):
    """A system.billing.usage row as Row.asDict(recursive=True) gives it."""
    row = {
        "record_id": "r1",
        "account_id": "acct-1",
        "workspace_id": "111",
        "sku_name": "PREMIUM_JOBS_SERVERLESS_COMPUTE_US_EAST_N_VIRGINIA",
        "cloud": "AWS",
        "usage_start_time": datetime(2026, 11, 20, 5, tzinfo=UTC),
        "usage_end_time": datetime(2026, 11, 20, 6, tzinfo=UTC),
        "usage_date": date(2026, 11, 20),
        "custom_tags": {"Project": "a"},
        "usage_unit": "DBU",
        "usage_quantity": Decimal("2.5"),
        "usage_metadata": {"job_id": "42", "cluster_id": None},
        "identity_metadata": {"run_as": "someone"},
        "record_type": "ORIGINAL",
        "ingestion_date": date(2026, 11, 20),
        "billing_origin_product": "JOBS",
        "product_features": {"is_serverless": True, "is_photon": False},
        "usage_type": "COMPUTE_TIME",
    }
    row.update(overrides)
    return row


def price_row(sku, start, value="0.35"):
    return {
        "price_start_time": start,
        "price_end_time": None,
        "account_id": "acct-1",
        "sku_name": sku,
        "cloud": "AWS",
        "currency_code": "USD",
        "usage_unit": "DBU",
        "pricing": {"default": Decimal(value), "promotional": {"default": None},
                    "effective_list": {"default": Decimal(value)}},
    }


class PeriodsTest(unittest.TestCase):
    def test_recent_periods_are_the_previous_and_current_month(self):
        self.assertEqual(export.periods_to_export("recent", date(2026, 11, 21), lambda: []), ["2026-10", "2026-11"])

    def test_recent_periods_cross_the_year(self):
        self.assertEqual(export.periods_to_export("recent", date(2026, 1, 3), lambda: []), ["2025-12", "2026-01"])

    def test_all_uses_every_available_month_sorted(self):
        self.assertEqual(export.periods_to_export("all", date(2026, 11, 21), lambda: ["2026-02", "2025-12"]),
                         ["2025-12", "2026-02"])

    def test_explicit_months(self):
        self.assertEqual(export.periods_to_export("2026-09, 2026-10", date(2026, 11, 21), lambda: []),
                         ["2026-09", "2026-10"])

    def test_bad_periods_are_rejected(self):
        for spec in ("", "last", "2026-13", "2026-9", "2026-09,,2026-10"):
            with self.subTest(spec=spec), self.assertRaises(ValueError):
                export.periods_to_export(spec, date(2026, 11, 21), lambda: [])

    def test_month_bounds_and_keys(self):
        self.assertEqual(export.month_bounds("2026-12"), ("2026-12-01", "2027-01-01"))
        self.assertEqual(export.run_stamp(datetime(2026, 11, 21, 6, 0, 7, tzinfo=UTC)), "20261121T060007Z")
        self.assertEqual(export.usage_key("raw/p", "2026-11", "R"),
                         "raw/p/table=usage/billing_period=2026-11/run=R/part-0.parquet")
        self.assertEqual(export.table_key("raw/p", "list_prices", "R"), "raw/p/table=list_prices/run=R/part-0.parquet")


class ParquetTest(unittest.TestCase):
    def test_written_usage_has_map_struct_and_decimal_types(self):
        body = export.to_parquet([usage_row()], export.USAGE_SCHEMA, export.SORT_KEYS["usage"])
        table = pq.read_table(io.BytesIO(body))

        self.assertTrue(pa.types.is_map(table.schema.field("custom_tags").type))
        self.assertTrue(pa.types.is_struct(table.schema.field("usage_metadata").type))
        self.assertEqual(table.schema.field("usage_quantity").type, pa.decimal128(38, 18))
        self.assertEqual(table.schema.field("usage_date").type, pa.date32())
        row = table.to_pylist()[0]
        self.assertEqual(row["custom_tags"], [("Project", "a")])
        self.assertEqual(row["usage_metadata"]["job_id"], "42")
        self.assertEqual(row["usage_quantity"], Decimal("2.5"))

    def test_unknown_fields_are_dropped(self):
        plain = export.to_parquet([usage_row()], export.USAGE_SCHEMA, export.SORT_KEYS["usage"])
        extra = usage_row(new_column="x", usage_metadata={"job_id": "42", "cluster_id": None, "new_field": "y"})
        self.assertEqual(export.to_parquet([extra], export.USAGE_SCHEMA, export.SORT_KEYS["usage"]), plain)

    def test_parquet_is_byte_identical_for_the_same_rows(self):
        a = price_row("SKU_A", datetime(2026, 1, 1, tzinfo=UTC))
        b = price_row("SKU_B", datetime(2026, 1, 1, tzinfo=UTC))
        keys = export.SORT_KEYS["list_prices"]
        self.assertEqual(export.to_parquet([a, b], export.PRICES_SCHEMA, keys),
                         export.to_parquet([b, a], export.PRICES_SCHEMA, keys))


class FakeTables:
    """A fake `query` that answers the export's SQL, and a fake `put` that keeps what is written."""

    def __init__(self, usage=None, periods=None, workspaces=None):
        self.usage = usage or {}
        self.periods = periods or []
        self.workspaces = workspaces or []
        self.queries = []
        self.written = {}

    def query(self, sql):
        self.queries.append(sql)
        if sql == export.PRICES_QUERY:
            return [price_row("SKU_A", datetime(2026, 1, 1, tzinfo=UTC))]
        if sql == export.PERIODS_QUERY:
            return [{"period": p} for p in self.periods]
        if sql == export.WORKSPACES_QUERY:
            return self.workspaces
        for period, rows in self.usage.items():
            start, end = export.month_bounds(period)
            if sql == export.USAGE_QUERY.format(start=start, end=end):
                return rows
        if sql.startswith("SELECT * FROM system.billing.usage"):
            return []
        raise AssertionError(f"unexpected query {sql!r}")

    def put(self, key, body):
        self.written[key] = body


NOW = datetime(2026, 11, 21, 6, 0, tzinfo=UTC)
P = "raw/provider=databricks/source=system-tables"


class ExportTest(unittest.TestCase):
    def test_recent_export_writes_prices_then_each_period(self):
        tables = FakeTables(usage={"2026-11": [usage_row()]})

        keys = export.export(tables.query, tables.put, prefix=P, periods="recent", include_workspaces=False, now=NOW)

        self.assertEqual(keys, [
            f"{P}/table=list_prices/run=20261121T060000Z/part-0.parquet",
            f"{P}/table=usage/billing_period=2026-10/run=20261121T060000Z/part-0.parquet",
            f"{P}/table=usage/billing_period=2026-11/run=20261121T060000Z/part-0.parquet",
        ])
        self.assertEqual(list(tables.written), keys)
        self.assertIn(export.USAGE_QUERY.format(start="2026-10-01", end="2026-11-01"), tables.queries)
        self.assertIn(export.USAGE_QUERY.format(start="2026-11-01", end="2026-12-01"), tables.queries)
        self.assertNotIn(export.WORKSPACES_QUERY, tables.queries)
        november = pq.read_table(io.BytesIO(tables.written[keys[2]]))
        self.assertEqual(november.num_rows, 1)

    def test_workspaces_are_exported_when_included(self):
        tables = FakeTables(workspaces=[{"workspace_id": "111", "workspace_name": "acme-shared",
                                         "workspace_url": "https://x", "status": "RUNNING"}])

        keys = export.export(tables.query, tables.put, prefix=P, periods="2026-11", include_workspaces=True, now=NOW)

        self.assertEqual(keys[1], f"{P}/table=workspaces/run=20261121T060000Z/part-0.parquet")
        self.assertEqual(pq.read_table(io.BytesIO(tables.written[keys[1]])).to_pylist()[0]["workspace_name"], "acme-shared")

    def test_all_exports_every_month_the_table_has(self):
        tables = FakeTables(periods=["2026-01", "2025-12"])

        keys = export.export(tables.query, tables.put, prefix=P, periods="all", include_workspaces=False, now=NOW)

        self.assertEqual([k.split("/")[4] for k in keys[1:]], ["billing_period=2025-12", "billing_period=2026-01"])

    def test_an_empty_period_writes_an_empty_snapshot(self):
        tables = FakeTables()

        keys = export.export(tables.query, tables.put, prefix=P, periods="2026-11", include_workspaces=False, now=NOW)

        empty = pq.read_table(io.BytesIO(tables.written[keys[1]]))
        self.assertEqual(empty.num_rows, 0)
        self.assertEqual(empty.schema, export.USAGE_SCHEMA)

    def test_nothing_is_written_when_periods_is_malformed(self):
        tables = FakeTables()

        with self.assertRaises(ValueError):
            export.export(tables.query, tables.put, prefix=P, periods="soon", include_workspaces=False, now=NOW)

        self.assertEqual(tables.written, {})
        self.assertEqual(tables.queries, [])


if __name__ == "__main__":
    unittest.main()
