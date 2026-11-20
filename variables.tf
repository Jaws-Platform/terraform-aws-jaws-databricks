variable "account_id" {
  description = "Databricks account ID (a UUID). It is also the external ID the audit log delivery role requires from Databricks."
  type        = string
}

variable "name_root" {
  description = "Prefix of every name this module derives, in kebab-case, for example `acme`: the metastore `<name_root>-us-east-1`, its admin group `<name_root>-metastore-admins`, the audit log bucket `<name_root>-databricks-audit-logs`, the log delivery role `<name_root>-databricks-log-delivery` and the host workspace `<name_root>-shared`. Each can be set on its own instead."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_root))
    error_message = "name_root must be kebab-case: lowercase letters, digits and single hyphens, for example `acme`; change the name_root variable."
  }
}

variable "admin_user_names" {
  description = "Databricks user names (email addresses) of the people who administer the metastore, for example `[\"owner@example.com\"]`. Each user must already exist in the account."
  type        = list(string)
}

variable "service_principal_application_id" {
  description = "Application (client) ID of the account-level service principal that automation authenticates as. It joins the metastore admin group, so automation keeps control of the metastore, and it becomes an admin of the host workspace."
  type        = string
}

variable "tags" {
  description = "Tags on the host workspace (`custom_tags`): must contain `Project`, `Environment`, `CostCenter`, `Owner` and `ManagedBy`, and no key Databricks reserves (`Vendor`, `Creator`, `ClusterName`, `ClusterId`, `Name`). `Workspace` defaults to the host workspace's name. Not needed when `host_workspace.enabled` is false; AWS resources take their tags from the provider's `default_tags`."
  type        = map(string)
  default     = {}
}

variable "metastore_name" {
  description = "Name of the Unity Catalog metastore. Null names it `<name_root>-us-east-1`. An account has one metastore per region, shared by every workspace there."
  type        = string
  default     = null
}

variable "admin_group_name" {
  description = "Name of the account-level group that owns the metastore. Null names it `<name_root>-metastore-admins`."
  type        = string
  default     = null
}

variable "audit_logs" {
  description = "Delivery of the account's audit logs (JSON) to a private, versioned S3 bucket. `bucket_name` and `role_name` default to `<name_root>-databricks-audit-logs` and `<name_root>-databricks-log-delivery`; Databricks may write under `<prefix>/` only. Set `enabled = false` to skip it, for example when another stack already delivers the account's audit logs."
  type = object({
    enabled     = optional(bool, true)
    bucket_name = optional(string)
    role_name   = optional(string)
    prefix      = optional(string, "audit")
  })
  default = {}
}

variable "host_workspace" {
  description = "The shared-objects host: a serverless workspace with no VPC, NAT, bucket, catalog or users, through which metastore-level objects that belong to no project (shared datasets) are created. `name` defaults to `<name_root>-shared` (at most 30 characters). Set `enabled = false` if nothing will be shared across workspaces."
  type = object({
    enabled = optional(bool, true)
    name    = optional(string)
  })
  default = {}

  validation {
    condition     = !var.host_workspace.enabled || length(coalesce(var.host_workspace.name, "${var.name_root}-shared")) <= 30
    error_message = "the host workspace's name (host_workspace.name, or `<name_root>-shared` without it) must be at most 30 characters; set host_workspace.name to a shorter name."
  }
}
