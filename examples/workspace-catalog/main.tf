# Stack 3 of 4, applied once per project after its account stack
# (project-workspace): the project's own Unity Catalog catalog and the
# workspace's compute policies and settings. Its inputs are the account
# stack's outputs.

variable "workspace_url" {
  description = "URL of the project's workspace: the account stack's `workspace_url` output."
  type        = string
}

variable "workspace_id" {
  description = "Numeric ID of the project's workspace: the account stack's `workspace_id` output."
  type        = number
}

variable "admin_group_name" {
  description = "The account stack's `admin_group_name` output."
  type        = string
}

variable "users_group_name" {
  description = "The account stack's `users_group_name` output."
  type        = string
}

variable "metastore_id" {
  description = "ID of the region's metastore: the account stack's `metastore_id` output."
  type        = string
}

variable "apply_role_arn" {
  description = "ARN of the role that applies this stack. It may list and delete objects in the catalog bucket, so a destroy can empty it, and never read or write them."
  type        = string
}

locals {
  name_root = "acme"
  project   = "analytics"

  # The governance tags, pinned on every cluster a user creates through a
  # policy and recorded as the catalog's properties.
  tags = {
    Project     = local.project
    Environment = "dev"
    CostCenter  = "cc-0042"
    Workspace   = "analytics-dev"
    Owner       = "data-team"
    ManagedBy   = "terraform"
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = local.tags
  }
}

# The workspace-level API of the workspace the account stack created.
# Authentication comes from the environment (DATABRICKS_CLIENT_ID and
# DATABRICKS_CLIENT_SECRET): the same service principal, which the account
# stack made a workspace admin.
provider "databricks" {
  host = var.workspace_url
}

# The catalog `analytics`, on managed storage in a bucket that only Unity
# Catalog can read or write.
module "catalog" {
  source = "../../modules/databricks-catalog"

  name_root        = local.name_root
  project          = local.project
  workspace_id     = var.workspace_id
  admin_group_name = var.admin_group_name
  users_group_name = var.users_group_name
  apply_role_arn   = var.apply_role_arn

  tags = local.tags
}

# Users may create clusters only through these policies, every cluster carries
# the governance tags, and none runs without auto-termination.
module "workspace_config" {
  source = "../../modules/databricks-workspace-config"

  users_group_name = var.users_group_name
  metastore_id     = var.metastore_id
  fixed_tags       = local.tags

  compute_policies = {
    analytics-jobs = {
      description = "Small autoscaling jobs compute"
      definition = jsonencode({
        autotermination_minutes = { type = "fixed", value = 30, hidden = true }
        node_type_id            = { type = "allowlist", values = ["m5.xlarge", "m5.2xlarge"] }
      })
    }
    analytics-shared = {
      description = "Shared all-purpose compute"
      definition = jsonencode({
        autotermination_minutes = { type = "fixed", value = 60 }
        cluster_type            = { type = "fixed", value = "all-purpose" }
        num_workers             = { type = "range", maxValue = 2 }
      })
    }
  }
}

output "catalog_name" {
  description = "The project's catalog."
  value       = module.catalog.catalog_name
}

output "cluster_policy_ids" {
  description = "IDs of the compute policies, by name."
  value       = module.workspace_config.cluster_policy_ids
}
