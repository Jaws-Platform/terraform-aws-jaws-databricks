variable "name" {
  description = "Names the IAM role, the service credential, the job and the script's folder in the applying identity's home (`<home>/<name>/`)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{1,48}$", var.name))
    error_message = "name must be 1 to 48 lowercase letters, digits or hyphens."
  }
}

variable "bucket_name" {
  description = "The billing bucket the snapshots are written to (`billing-bucket` of Jaws-Platform/jaws-monitoring/aws)."
  type        = string
}

variable "prefix" {
  description = <<-EOT
    Where the snapshots are written in the bucket, with no leading or trailing
    slash: the Databricks source prefix that `billing-normalizer` reads.
  EOT
  type        = string
  default     = "raw/provider=databricks/source=system-tables"

  validation {
    condition     = length(var.prefix) > 0 && !startswith(var.prefix, "/") && !endswith(var.prefix, "/") && !strcontains(var.prefix, "//")
    error_message = "prefix must be non-empty, with no leading, trailing or doubled slash."
  }
}

variable "owner_group_name" {
  description = "The group that owns the service credential, usually the metastore admins."
  type        = string
}

variable "include_workspaces" {
  description = <<-EOT
    Also export `system.access.workspaces_latest` (workspace IDs and names), and
    grant the job's identity that schema. The `access` system schema must be
    enabled in the metastore first.
  EOT
  type        = bool
  default     = false
}

variable "schedule" {
  description = "When the job runs: a Quartz cron expression in `timezone`, and whether the schedule is paused."
  type = object({
    cron     = optional(string, "0 0 6 * * ?")
    timezone = optional(string, "UTC")
    paused   = optional(bool, false)
  })
  default = {}
}

variable "environment_version" {
  description = "The serverless environment version the job runs in."
  type        = string
  default     = "3"
}

variable "job_tags" {
  description = "Tags on the Databricks job."
  type        = map(string)
  default     = {}
}

variable "component" {
  description = "Value of the `Component` tag on every AWS resource."
  type        = string
  default     = "databricks-billing-export"
}
