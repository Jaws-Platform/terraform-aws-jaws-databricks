# databricks-billing-export

Part of [`Jaws-Platform/jaws-databricks/aws`](https://registry.terraform.io/modules/Jaws-Platform/jaws-databricks/aws/latest) · [Registry](https://registry.terraform.io/modules/Jaws-Platform/jaws-databricks/aws/latest/submodules/databricks-billing-export) · [Source](https://github.com/Jaws-Platform/terraform-aws-jaws-databricks/tree/main/modules/databricks-billing-export)

A daily serverless job, in one workspace (the account's shared-objects host),
that writes whole-billing-period snapshots of Databricks' billing system
tables to an S3 bucket, so a cost pipeline outside Databricks can read them
with no SQL warehouse. The layout is the Databricks source of
[`billing-normalizer`](https://registry.terraform.io/modules/Jaws-Platform/jaws-monitoring/aws/latest/submodules/billing-normalizer)
(Jaws-Platform/jaws-monitoring/aws), which turns them into FOCUS-aligned
cost rows at list price.

Applied with the workspace-level `databricks` provider and the AWS provider
of the bucket's account. What it creates:

- a Unity Catalog **service credential** (`<name>`), owned by
  `owner_group_name`, on an IAM role (`<name>`) that may only
  `s3:PutObject` under `prefix`: the job can add snapshots and do nothing
  else in the bucket;
- the script, `files/billing_export.py`, as the workspace file
  `/Shared/<name>/billing_export.py`;
- the **job** (`<name>`): one Python-file task on serverless jobs compute in
  standard performance mode, daily at 06:00 UTC, one run at a time, retried
  twice;
- **additive grants** (`databricks_grant`, never authoritative, so other
  grants on the shared `system` catalog stay) to the identity that applies
  the module, which the job runs as: `USE_CATALOG` on `system`,
  `USE_SCHEMA` and `SELECT` on `system.billing` (and `system.access` with
  `include_workspaces`), and `ACCESS` on the credential.

The role carries `Name` and `Component`; every other AWS tag comes from the
caller's provider `default_tags`.

## What it writes

```text
s3://<bucket_name>/<prefix>/
  table=list_prices/run=<YYYYMMDDTHHMMSSZ>/part-0.parquet                    system.billing.list_prices
  table=workspaces/run=<…>/part-0.parquet   (include_workspaces)             system.access.workspaces_latest
  table=usage/billing_period=YYYY-MM/run=<…>/part-0.parquet  (each period)   system.billing.usage
```

Every run writes new objects; nothing is overwritten or deleted. Each object
has an explicit schema (fields Databricks adds later are left out, so the
output never changes shape) and sorted rows, so unchanged content gives the
same bytes and the same ETag, and the normalizer rebuilds nothing.

The job parameter `periods` chooses what is exported:

- `recent` (the default): the previous and the current UTC month, which
  covers late-arriving usage and corrections (`RETRACTION` and `RESTATEMENT`
  rows);
- `all`: every month in `system.billing.usage`, the **backfill**: run the
  job once by hand with `periods = all`; system tables keep their history
  indefinitely;
- `YYYY-MM[,YYYY-MM…]`: those months.

## Identity, credential and cost

The job runs as whoever applies the module, usually the automation service
principal that manages the workspace, and that identity is granted what the
job reads. The job's access to AWS is the service credential's role alone,
reached through `dbutils.credentials.getServiceCredentialsProvider`, as
Databricks documents. The credential is open rather than bound to one
workspace: only its owner group and the principals granted `ACCESS` can use
it, and it can only put objects under `prefix`.

`include_workspaces` needs the `access` system schema enabled in the
metastore. Without it, workspace names come from the normalizer's
`workspace_names` input.

Serverless jobs in standard performance mode bill per DBU with a one-minute
minimum per run, so the daily run costs cents a month. Its own spend appears
in the snapshots it writes.

## Usage

```hcl
module "billing_export" {
  source  = "Jaws-Platform/jaws-databricks/aws//modules/databricks-billing-export"
  version = "0.1.2" # x-release-please-version

  name             = "acme-billing-export"
  bucket_name      = "acme-billing"
  owner_group_name = "acme-metastore-admins"
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| aws | ~> 6.0 |
| databricks | >= 1.142, < 2.0 |
| time | ~> 0.13 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | ~> 6.0 |
| databricks | >= 1.142, < 2.0 |
| time | ~> 0.13 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [databricks_credential.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/credential) | resource |
| [databricks_grant.access](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/grant) | resource |
| [databricks_grant.billing](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/grant) | resource |
| [databricks_grant.credential](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/grant) | resource |
| [databricks_grant.system_catalog](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/grant) | resource |
| [databricks_job.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/job) | resource |
| [databricks_workspace_file.script](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/workspace_file) | resource |
| [time_sleep.role_propagation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [databricks_aws_unity_catalog_assume_role_policy.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/aws_unity_catalog_assume_role_policy) | data source |
| [databricks_current_user.me](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/current_user) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| bucket\_name | The billing bucket the snapshots are written to (`billing-bucket` of Jaws-Platform/jaws-monitoring/aws). | `string` | n/a | yes |
| name | Names the IAM role, the service credential, the job and the workspace folder (`/Shared/<name>/`). | `string` | n/a | yes |
| owner\_group\_name | The group that owns the service credential, usually the metastore admins. | `string` | n/a | yes |
| component | Value of the `Component` tag on every AWS resource. | `string` | `"databricks-billing-export"` | no |
| environment\_version | The serverless environment version the job runs in. | `string` | `"3"` | no |
| include\_workspaces | Also export `system.access.workspaces_latest` (workspace IDs and names), and<br/>grant the job's identity that schema. The `access` system schema must be<br/>enabled in the metastore first. | `bool` | `false` | no |
| job\_tags | Tags on the Databricks job. | `map(string)` | `{}` | no |
| prefix | Where the snapshots are written in the bucket, with no leading or trailing<br/>slash: the Databricks source prefix that `billing-normalizer` reads. | `string` | `"raw/provider=databricks/source=system-tables"` | no |
| schedule | When the job runs: a Quartz cron expression in `timezone`, and whether the schedule is paused. | <pre>object({<br/>    cron     = optional(string, "0 0 6 * * ?")<br/>    timezone = optional(string, "UTC")<br/>    paused   = optional(bool, false)<br/>  })</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| credential\_name | The Unity Catalog service credential the job writes through. |
| job\_id | The job's ID: run it once with the job parameter `periods = all` to backfill. |
| job\_name | The job's name. |
| prefix | Where the snapshots are written in the bucket. |
| role\_arn | The credential's IAM role ARN, known at plan. |
| role\_name | The credential's IAM role. |
| run\_as | The identity the job runs as and the grants are given to: whoever applied the module. |
<!-- END_TF_DOCS -->
