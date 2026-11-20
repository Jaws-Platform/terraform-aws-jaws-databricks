output "metastore_id" {
  description = "ID of the Unity Catalog metastore: the `metastore_id` input of `databricks-workspace` and `databricks-workspace-config`."
  value       = module.metastore.metastore_id
}

output "metastore_name" {
  description = "Name of the metastore, for stacks that look it up with the `databricks_metastore` data source instead of taking its ID."
  value       = local.metastore_name
}

output "admin_group_name" {
  description = "Name of the account group that owns the metastore: the `owner_group_name` input of the dataset modules."
  value       = module.metastore.admin_group_name
}

output "audit_log_bucket_name" {
  description = "Name of the audit log bucket. Null when `audit_logs.enabled` is false."
  value       = one(module.audit_logs[*].bucket_name)
}

output "audit_log_bucket_arn" {
  description = "ARN of the audit log bucket, for the IAM policies of principals that share it under another prefix. Null when `audit_logs.enabled` is false."
  value       = one(module.audit_logs[*].bucket_arn)
}

output "log_delivery_config_id" {
  description = "ID of the Databricks audit log delivery configuration. Null when `audit_logs.enabled` is false."
  value       = one(module.audit_logs[*].log_delivery_config_id)
}

output "host_workspace_id" {
  description = "Numeric ID of the host workspace: the `host_workspace_id` input of the dataset modules. Null when `host_workspace.enabled` is false."
  value       = one(module.host_workspace[*].workspace_id)
}

output "host_workspace_url" {
  description = "URL of the host workspace: the `host` of the workspace-level `databricks` provider that the dataset modules are applied through. Null when `host_workspace.enabled` is false."
  value       = one(module.host_workspace[*].workspace_url)
}
