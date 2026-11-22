output "job_id" {
  description = "The job's ID: run it once with the job parameter `periods = all` to backfill."
  value       = databricks_job.this.id
}

output "job_name" {
  description = "The job's name."
  value       = databricks_job.this.name
}

output "credential_name" {
  description = "The Unity Catalog service credential the job writes through."
  value       = databricks_credential.this.name
}

output "role_name" {
  description = "The credential's IAM role."
  value       = aws_iam_role.this.name
}

output "role_arn" {
  description = "The credential's IAM role ARN, known at plan."
  value       = local.role_arn
}

output "prefix" {
  description = "Where the snapshots are written in the bucket."
  value       = var.prefix
}

output "run_as" {
  description = "The identity the job runs as and the grants are given to: whoever applied the module."
  value       = local.run_as
}
