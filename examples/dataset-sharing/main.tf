# Stack 4 of 4, applied through the shared-objects host: one S3 dataset made
# readable, read-only, from a project's workspace, without copying it and
# without either project owning the grant.
#
#   producer  chess-selfplay   owns the bucket and decides who reads it
#   dataset   positions        s3://acme-chess-selfplay-positions/data/
#   consumer  analytics        reads /Volumes/chess_selfplay/positions/files/

variable "host_workspace_url" {
  description = "URL of the shared-objects host: the account-baseline stack's `host_workspace_url` output."
  type        = string
}

variable "host_workspace_id" {
  description = "Numeric ID of the shared-objects host: the account-baseline stack's `host_workspace_id` output."
  type        = number
}

variable "owner_group_name" {
  description = "The group that owns the metastore: the account-baseline stack's `admin_group_name` output."
  type        = string
}

variable "apply_role_arn" {
  description = "ARN of the role that applies this stack. It may list and delete objects in the catalog storage bucket, so a destroy can empty it, and never read or write them."
  type        = string
}

variable "consumer_workspace_id" {
  description = "Numeric ID of the consuming project's workspace: its account stack's `workspace_id` output."
  type        = number
}

variable "consumer_users_group_name" {
  description = "The consuming project's users group: its account stack's `users_group_name` output."
  type        = string
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "data-platform"
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}

# The workspace-level API of the host, as the same service principal: it is
# in the metastore admin group, the only group assigned to the host.
provider "databricks" {
  host = var.host_workspace_url
}

# Managed storage for the producer catalogs. The metastore has no storage
# root, so every catalog needs a managed location; nothing is written to this
# one, because the catalogs hold only external volumes.
module "catalog_storage" {
  source = "../../modules/databricks-catalog-storage"

  name              = "acme-dataset-catalogs"
  host_workspace_id = var.host_workspace_id
  owner_group_name  = var.owner_group_name
  apply_role_arn    = var.apply_role_arn
}

# One catalog per producer, owned by the platform: a catalog's owner can grant
# anyone access, so it is never the producer.
module "producer_catalog" {
  source = "../../modules/databricks-producer-catalog"

  producer          = "chess-selfplay"
  storage_url       = module.catalog_storage.url
  host_workspace_id = var.host_workspace_id
  owner_group_name  = var.owner_group_name

  # The storage URL is built from a name, so it carries no dependency: without
  # this the catalog could be created before the location it lives under.
  depends_on = [module.catalog_storage]
}

# Onboard the dataset once: a read-only role, storage credential and external
# location, and a schema in the producer's catalog holding the volume `files`.
# This grants nothing. The role can read only once the bucket's own policy
# names it, which stays the producer's decision.
module "positions" {
  source = "../../modules/databricks-dataset"

  name              = "acme-ds-chess-selfplay-positions"
  bucket            = "acme-chess-selfplay-positions"
  prefix            = "data/"
  host_workspace_id = var.host_workspace_id
  owner_group_name  = var.owner_group_name

  catalog_name = module.producer_catalog.catalog_name
  schema_name  = "positions"
}

locals {
  # The workspaces that producer and consumer have both agreed may read.
  consumers = {
    analytics = {
      workspace_id     = var.consumer_workspace_id
      users_group_name = var.consumer_users_group_name
    }
  }
}

# Who may see the producer's catalog at all.
module "producer_catalog_access" {
  source = "../../modules/databricks-producer-catalog-access"

  catalog_name     = module.producer_catalog.catalog_name
  owner_group_name = var.owner_group_name
  consumers        = local.consumers
}

# Who may read this dataset.
module "positions_access" {
  source = "../../modules/databricks-dataset-access"

  external_location_name  = module.positions.external_location_name
  storage_credential_name = module.positions.storage_credential_name
  owner_group_name        = var.owner_group_name
  schema_full_name        = module.positions.schema_full_name
  volume_full_name        = module.positions.volume_full_name
  consumers               = local.consumers
}

output "dataset_role_arn" {
  description = "The role to name as a reader in the dataset bucket's policy."
  value       = module.positions.role_arn
}

output "endpoint_dataset" {
  description = "The entry to add to the consuming workspace's `read_only_datasets`, so its S3 endpoint lets the role through."
  value       = module.positions.endpoint_dataset
}

output "volume_path" {
  description = "Where consumers read the dataset."
  value       = module.positions.volume_path
}
