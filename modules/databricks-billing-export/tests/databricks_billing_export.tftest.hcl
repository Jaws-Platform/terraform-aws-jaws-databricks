# The Databricks billing export: a daily serverless job, run as the identity
# that applies the module, writing billing snapshots through a service
# credential whose role may only put objects under one prefix. Mock providers:
# nothing is called.

mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }
}

mock_provider "databricks" {
  override_during = plan

  mock_data "databricks_current_user" {
    defaults = {
      user_name = "11111111-2222-3333-4444-555555555555"
    }
  }

  mock_data "databricks_aws_unity_catalog_assume_role_policy" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "databricks_workspace_file" {
    defaults = {
      workspace_path = "/Workspace/Shared/acme-billing-export/billing_export.py"
    }
  }
}

mock_provider "time" {}

variables {
  name             = "acme-billing-export"
  bucket_name      = "acme-billing"
  owner_group_name = "acme-metastore-admins"
}

run "the_credential_is_a_service_credential_on_a_built_role" {
  command = plan

  assert {
    condition = (databricks_credential.this.name == "acme-billing-export"
      && databricks_credential.this.purpose == "SERVICE"
      && databricks_credential.this.aws_iam_role[0].role_arn == "arn:aws:iam::123456789012:role/acme-billing-export"
      && databricks_credential.this.skip_validation
      && databricks_credential.this.isolation_mode == "ISOLATION_MODE_OPEN"
    && databricks_credential.this.owner == "acme-metastore-admins")
    error_message = "one SERVICE credential named var.name, on the role ARN built from the name, owned by the owner group"
  }
}

run "the_role_may_only_put_under_the_databricks_prefix" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role_policy.this.policy).Statement == [
      {
        Sid      = "PutSnapshots"
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::acme-billing/raw/provider=databricks/source=system-tables/*"
      },
      {
        Sid      = "SelfAssume"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = "arn:aws:iam::123456789012:role/acme-billing-export"
      },
    ]
    error_message = "the role may put objects under the Databricks prefix, and assume itself as Databricks requires; nothing else"
  }

  assert {
    condition     = aws_iam_role.this.name == "acme-billing-export" && aws_iam_role.this.tags == tomap({ Name = "acme-billing-export", Component = "databricks-billing-export" })
    error_message = "the role is named var.name and carries Name and Component"
  }
}

run "the_applying_identity_may_read_billing_and_use_the_credential" {
  command = plan

  assert {
    condition = (databricks_grant.system_catalog.catalog == "system"
      && toset(databricks_grant.system_catalog.privileges) == toset(["USE_CATALOG"])
    && databricks_grant.system_catalog.principal == "11111111-2222-3333-4444-555555555555")
    error_message = "the applying identity may use the system catalog"
  }

  assert {
    condition = (databricks_grant.billing.schema == "system.billing"
      && toset(databricks_grant.billing.privileges) == toset(["USE_SCHEMA", "SELECT"])
    && databricks_grant.billing.principal == "11111111-2222-3333-4444-555555555555")
    error_message = "the applying identity may read system.billing"
  }

  assert {
    condition = (databricks_grant.credential.credential == "acme-billing-export"
      && toset(databricks_grant.credential.privileges) == toset(["ACCESS"])
    && databricks_grant.credential.principal == "11111111-2222-3333-4444-555555555555")
    error_message = "the applying identity may use the service credential"
  }

  assert {
    condition     = length(databricks_grant.access) == 0
    error_message = "system.access is not granted unless workspaces are included"
  }
}

run "workspaces_are_opt_in" {
  command = plan

  variables {
    include_workspaces = true
  }

  assert {
    condition     = length(databricks_grant.access) == 1 && databricks_grant.access[0].schema == "system.access" && toset(databricks_grant.access[0].privileges) == toset(["USE_SCHEMA", "SELECT"])
    error_message = "with include_workspaces the identity may read system.access"
  }

  assert {
    condition     = contains(databricks_job.this.task[0].spark_python_task[0].parameters, "--include-workspaces") && element(databricks_job.this.task[0].spark_python_task[0].parameters, index(databricks_job.this.task[0].spark_python_task[0].parameters, "--include-workspaces") + 1) == "true"
    error_message = "the job is told to export the workspaces"
  }
}

run "the_job_is_a_daily_serverless_python_task" {
  command = plan

  assert {
    condition     = databricks_job.this.name == "acme-billing-export" && databricks_job.this.performance_target == "STANDARD" && databricks_job.this.max_concurrent_runs == 1 && databricks_job.this.timeout_seconds == 3600
    error_message = "one run at a time, in standard performance mode, for at most an hour"
  }

  assert {
    condition     = databricks_job.this.schedule[0].quartz_cron_expression == "0 0 6 * * ?" && databricks_job.this.schedule[0].timezone_id == "UTC" && databricks_job.this.schedule[0].pause_status == "UNPAUSED"
    error_message = "daily at 06:00 UTC"
  }

  assert {
    condition = (length(databricks_job.this.task) == 1
      && databricks_job.this.task[0].task_key == "export"
      && databricks_job.this.task[0].environment_key == "default"
      && length(databricks_job.this.task[0].new_cluster) == 0
      && databricks_job.this.task[0].max_retries == 2
    && databricks_job.this.task[0].spark_python_task[0].python_file == "/Workspace/Shared/acme-billing-export/billing_export.py")
    error_message = "one serverless Python-file task, retried twice"
  }

  assert {
    condition = databricks_job.this.task[0].spark_python_task[0].parameters == tolist([
      "--bucket", "acme-billing",
      "--prefix", "raw/provider=databricks/source=system-tables",
      "--credential", "acme-billing-export",
      "--region", "us-east-1",
      "--periods", "{{job.parameters.periods}}",
      "--include-workspaces", "false",
    ])
    error_message = "the script gets the bucket, prefix, credential, region, the periods job parameter and the workspace switch"
  }

  assert {
    condition     = length(databricks_job.this.parameter) == 1 && databricks_job.this.parameter[0].name == "periods" && databricks_job.this.parameter[0].default == "recent"
    error_message = "one job parameter, periods, defaulting to recent (all is the backfill)"
  }

  assert {
    condition     = databricks_job.this.environment[0].environment_key == "default" && databricks_job.this.environment[0].spec[0].environment_version == "3" && databricks_job.this.environment[0].spec[0].dependencies == tolist(["pyarrow==21.0.0", "boto3==1.40.0"])
    error_message = "serverless environment 3 with pyarrow and boto3 pinned"
  }
}

run "the_script_is_uploaded_to_the_shared_folder" {
  command = plan

  assert {
    condition     = databricks_workspace_file.script.path == "/Shared/acme-billing-export/billing_export.py" && endswith(databricks_workspace_file.script.source, "files/billing_export.py")
    error_message = "the module's script is the workspace file the task runs"
  }
}

run "the_schedule_is_an_input" {
  command = plan

  variables {
    schedule = { cron = "0 30 7 * * ?", paused = true }
  }

  assert {
    condition     = databricks_job.this.schedule[0].quartz_cron_expression == "0 30 7 * * ?" && databricks_job.this.schedule[0].pause_status == "PAUSED"
    error_message = "schedule sets the cron and can pause the job"
  }
}

run "rejects_prefixes_with_stray_slashes" {
  command = plan

  variables {
    prefix = "raw//databricks/"
  }

  expect_failures = [var.prefix]
}

run "rejects_an_invalid_name" {
  command = plan

  variables {
    name = "Acme Billing"
  }

  expect_failures = [var.name]
}
