# Root module: the baseline of one Databricks account on AWS, applied once.
#
#   databricks-metastore        the region's Unity Catalog metastore and the
#                               admin group that owns it
#   databricks-audit-logs       account audit logs delivered to a private bucket
#   databricks-host-workspace   a serverless workspace that owns the objects no
#                               project owns (shared datasets), at no standing cost
#
# Everything here uses the account-level `databricks` provider. Project
# workspaces, their catalogs and shared datasets are separate stacks built
# from the submodules, because each needs a provider that points at a
# workspace this stack (or theirs) creates first. The README walks through
# the order.

locals {
  metastore_name         = coalesce(var.metastore_name, "${var.name_root}-us-east-1")
  admin_group_name       = coalesce(var.admin_group_name, "${var.name_root}-metastore-admins")
  audit_bucket_name      = coalesce(var.audit_logs.bucket_name, "${var.name_root}-databricks-audit-logs")
  log_delivery_role_name = coalesce(var.audit_logs.role_name, "${var.name_root}-databricks-log-delivery")
  host_workspace_name    = coalesce(var.host_workspace.name, "${var.name_root}-shared")
}

module "metastore" {
  source = "./modules/databricks-metastore"

  name                             = local.metastore_name
  admin_group_name                 = local.admin_group_name
  admin_user_names                 = var.admin_user_names
  service_principal_application_id = var.service_principal_application_id
}

module "audit_logs" {
  source = "./modules/databricks-audit-logs"
  count  = var.audit_logs.enabled ? 1 : 0

  account_id  = var.account_id
  bucket_name = local.audit_bucket_name
  role_name   = local.log_delivery_role_name
  prefix      = var.audit_logs.prefix
}

module "host_workspace" {
  source = "./modules/databricks-host-workspace"
  count  = var.host_workspace.enabled ? 1 : 0

  account_id       = var.account_id
  workspace_name   = local.host_workspace_name
  metastore_id     = module.metastore.metastore_id
  admin_group_name = module.metastore.admin_group_name

  # The workspace is tagged with its own name unless the caller says otherwise.
  tags = merge({ Workspace = local.host_workspace_name }, var.tags)

  # The submodule looks the admin group up by name. In a fresh account the
  # group is created in this same apply, so the lookup has to wait for it.
  depends_on = [module.metastore]
}
