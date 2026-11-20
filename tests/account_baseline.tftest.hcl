mock_provider "aws" {
  override_during = plan

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::acme-databricks-audit-logs"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111122223333:role/acme-databricks-log-delivery"
    }
  }
}

mock_provider "databricks" {
  override_during = plan

  # The host workspace assigns the admin group by its numeric ID.
  mock_resource "databricks_group" {
    defaults = {
      id = "1111"
    }
  }

  mock_data "databricks_group" {
    defaults = {
      id = "1111"
    }
  }

  mock_resource "databricks_metastore" {
    defaults = {
      metastore_id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    }
  }

  mock_resource "databricks_mws_workspaces" {
    defaults = {
      workspace_id  = 1234567890123456
      workspace_url = "https://dbc-01234567-89ab.cloud.databricks.com"
    }
  }
}

mock_provider "time" {}

variables {
  account_id                       = "11111111-2222-3333-4444-555555555555"
  name_root                        = "acme"
  admin_user_names                 = ["owner@example.com"]
  service_principal_application_id = "00000000-0000-0000-0000-000000000000"

  tags = {
    Project     = "data-platform"
    Environment = "prod"
    CostCenter  = "platform"
    Owner       = "platform-team"
    ManagedBy   = "terraform"
  }
}

run "every_name_derives_from_name_root" {
  command = plan

  assert {
    condition     = local.metastore_name == "acme-us-east-1" && local.admin_group_name == "acme-metastore-admins"
    error_message = "the metastore and its admin group must be named after name_root"
  }

  assert {
    condition     = local.audit_bucket_name == "acme-databricks-audit-logs" && local.log_delivery_role_name == "acme-databricks-log-delivery"
    error_message = "the audit log bucket and delivery role must be named after name_root"
  }

  assert {
    condition     = local.host_workspace_name == "acme-shared"
    error_message = "the host workspace must be named <name_root>-shared"
  }
}

run "the_whole_baseline_by_default" {
  command = plan

  assert {
    condition     = length(module.audit_logs) == 1 && length(module.host_workspace) == 1
    error_message = "audit logs and the host workspace must both be created by default"
  }

  assert {
    condition     = output.metastore_id == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" && output.metastore_name == "acme-us-east-1"
    error_message = "the metastore outputs must describe the metastore module's metastore"
  }

  assert {
    condition     = output.admin_group_name == "acme-metastore-admins"
    error_message = "admin_group_name must be the group that owns the metastore"
  }

  assert {
    condition     = output.audit_log_bucket_arn == "arn:aws:s3:::acme-databricks-audit-logs"
    error_message = "the audit log outputs must be the audit-logs module's outputs"
  }

  assert {
    condition     = output.host_workspace_id == 1234567890123456 && output.host_workspace_url == "https://dbc-01234567-89ab.cloud.databricks.com"
    error_message = "the host outputs must be the host-workspace module's outputs"
  }
}

run "names_can_be_set_one_by_one" {
  command = plan

  variables {
    metastore_name   = "primary"
    admin_group_name = "metastore-owners"
    audit_logs       = { bucket_name = "acme-audit", role_name = "acme-audit-delivery", prefix = "databricks" }
    host_workspace   = { name = "acme-governance" }
  }

  assert {
    condition     = local.metastore_name == "primary" && local.admin_group_name == "metastore-owners"
    error_message = "metastore_name and admin_group_name must override the derived names"
  }

  assert {
    condition     = local.audit_bucket_name == "acme-audit" && local.log_delivery_role_name == "acme-audit-delivery"
    error_message = "audit_logs.bucket_name and role_name must override the derived names"
  }

  assert {
    condition     = local.host_workspace_name == "acme-governance"
    error_message = "host_workspace.name must override the derived name"
  }

  assert {
    condition     = output.metastore_name == "primary" && output.admin_group_name == "metastore-owners"
    error_message = "the outputs must follow the overridden names"
  }
}

run "audit_logs_can_be_left_to_another_stack" {
  command = plan

  variables {
    audit_logs = { enabled = false }
  }

  assert {
    condition     = length(module.audit_logs) == 0
    error_message = "audit_logs.enabled = false must create no audit log delivery"
  }

  assert {
    condition     = output.audit_log_bucket_name == null && output.audit_log_bucket_arn == null && output.log_delivery_config_id == null
    error_message = "the audit log outputs must be null without audit logs"
  }
}

run "the_host_workspace_is_optional" {
  command = plan

  variables {
    host_workspace = { enabled = false }
    tags           = {}
  }

  assert {
    condition     = length(module.host_workspace) == 0
    error_message = "host_workspace.enabled = false must create no workspace"
  }

  assert {
    condition     = output.host_workspace_id == null && output.host_workspace_url == null
    error_message = "the host outputs must be null without the host workspace"
  }

  assert {
    condition     = output.metastore_id != null
    error_message = "the metastore must still be created"
  }
}

run "rejects_a_derived_host_name_over_30_characters" {
  command = plan

  variables {
    name_root = "a-name-root-of-24-chars0"
  }

  expect_failures = [var.host_workspace]
}

run "a_long_name_root_is_fine_with_a_short_host_name" {
  command = plan

  variables {
    name_root      = "a-name-root-of-24-chars0"
    host_workspace = { name = "shared" }
  }

  assert {
    condition     = local.host_workspace_name == "shared" && local.metastore_name == "a-name-root-of-24-chars0-us-east-1"
    error_message = "an explicit host name must lift the limit on name_root"
  }
}

run "rejects_a_name_root_that_is_not_kebab_case" {
  command = plan

  variables {
    name_root = "Acme_Data"
  }

  expect_failures = [var.name_root]
}
