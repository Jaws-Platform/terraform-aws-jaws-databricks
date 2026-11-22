# The job, its script and what its identity is granted.

# In the applying identity's home folder, never /Shared: every workspace user
# can edit what is in /Shared, and the job runs this file as that identity.
resource "databricks_workspace_file" "script" {
  source = "${path.module}/files/billing_export.py"
  path   = "${data.databricks_current_user.me.home}/${var.name}/billing_export.py"
}

# Per-principal grants (databricks_grant, never the securable-wide
# databricks_grants): other principals' grants on the shared system catalog
# stay. Each one is authoritative for the job's identity on its securable,
# though: grant that identity on these securables nowhere else.
resource "databricks_grant" "system_catalog" {
  catalog    = "system"
  principal  = local.run_as
  privileges = ["USE_CATALOG"]
}

resource "databricks_grant" "billing" {
  schema     = "system.billing"
  principal  = local.run_as
  privileges = ["USE_SCHEMA", "SELECT"]
}

resource "databricks_grant" "access" {
  count = var.include_workspaces ? 1 : 0

  schema     = "system.access"
  principal  = local.run_as
  privileges = ["USE_SCHEMA", "SELECT"]
}

resource "databricks_grant" "credential" {
  credential = databricks_credential.this.name
  principal  = local.run_as
  privileges = ["ACCESS"]
}

resource "databricks_job" "this" {
  name                = var.name
  description         = "Daily snapshots of the Databricks billing system tables to s3://${var.bucket_name}/${var.prefix}/"
  performance_target  = "STANDARD"
  max_concurrent_runs = 1
  timeout_seconds     = 3600
  tags                = var.job_tags

  # `recent` is the previous and the current month; run once with `all` to backfill.
  parameter {
    name    = "periods"
    default = "recent"
  }

  schedule {
    quartz_cron_expression = var.schedule.cron
    timezone_id            = var.schedule.timezone
    pause_status           = var.schedule.paused ? "PAUSED" : "UNPAUSED"
  }

  environment {
    environment_key = "default"

    spec {
      environment_version = var.environment_version
      dependencies        = ["pyarrow==21.0.0", "boto3==1.40.0"]
    }
  }

  task {
    task_key                  = "export"
    environment_key           = "default"
    max_retries               = 2
    min_retry_interval_millis = 600000
    timeout_seconds           = 3600

    spark_python_task {
      python_file = databricks_workspace_file.script.workspace_path
      parameters = [
        "--bucket", var.bucket_name,
        "--prefix", var.prefix,
        "--credential", databricks_credential.this.name,
        "--region", data.aws_region.current.region,
        "--periods", "{{job.parameters.periods}}",
        "--include-workspaces", tostring(var.include_workspaces),
      ]
    }
  }

  depends_on = [
    databricks_grant.system_catalog,
    databricks_grant.billing,
    databricks_grant.access,
    databricks_grant.credential,
    time_sleep.role_propagation,
  ]
}
