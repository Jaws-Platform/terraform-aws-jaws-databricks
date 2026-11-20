# Stack 2 of 4, applied once per project: a VPC with private subnets, a NAT
# instance for their egress, and a Databricks workspace in that VPC. Its
# outputs are the inputs of the project's workspace stack (workspace-catalog).

variable "databricks_account_id" {
  description = "Databricks account ID (a UUID), from the account console."
  type        = string
}

variable "service_principal_application_id" {
  description = "Application (client) ID of the account-admin service principal Terraform authenticates as."
  type        = string
}

locals {
  name_root   = "acme"
  project     = "analytics"
  environment = "dev"
  name        = "${local.name_root}-${local.project}"

  # Two /20s in the upper half of the VPC, clear of the public /24s the
  # network module carves from its start. Databricks accepts subnets between
  # /17 and /26.
  vpc_cidr             = "10.0.0.0/16"
  private_subnet_cidrs = [cidrsubnet(local.vpc_cidr, 4, 8), cidrsubnet(local.vpc_cidr, 4, 9)]

  # Databricks puts these on every cluster resource of the workspace, which
  # the AWS provider's default_tags cannot reach.
  tags = {
    Project     = local.project
    Environment = local.environment
    CostCenter  = "cc-0042"
    Workspace   = "${local.project}-${local.environment}"
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

# The account-level API, as in the account-baseline stack.
provider "databricks" {
  host = "https://accounts.cloud.databricks.com"
}

# The region's metastore, created by the account-baseline stack and looked up
# by name, so the two stacks share no state.
data "databricks_metastore" "this" {
  name = "${local.name_root}-us-east-1"
}

# The NAT image is resolved from a pinned name, so a new Amazon Linux release
# does not replace the instance.
data "aws_ami" "nat" {
  owners             = ["amazon"]
  include_deprecated = true
  most_recent        = false

  filter {
    name   = "name"
    values = ["al2023-ami-2023.6.20250115.0-kernel-6.1-arm64"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

# The network family's root module: the VPC, its private subnets, a NAT
# instance and an S3 gateway endpoint. On the registry this is
# `Jaws-Platform/jaws-network/aws`.
module "network" {
  source = "git::https://github.com/Jaws-Platform/terraform-aws-jaws-network.git?ref=v0.1.0"

  name                 = local.name
  cidr_block           = local.vpc_cidr
  availability_zones   = ["us-east-1a", "us-east-1b"]
  private_subnet_cidrs = local.private_subnet_cidrs

  # The endpoint lets compute reach the catalog bucket only as the Unity
  # Catalog role. The policy is built from names alone, so taking it from the
  # workspace module is not a dependency cycle.
  s3_gateway_endpoint = {
    enabled = true
    policy  = module.workspace.s3_endpoint_policy
  }

  nat = { ami_id = data.aws_ami.nat.id }
}

module "workspace" {
  source = "../../modules/databricks-workspace"

  account_id      = var.databricks_account_id
  name_root       = local.name_root
  project         = local.project
  environment     = local.environment
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.private_subnet_ids
  metastore_id    = data.databricks_metastore.this.metastore_id
  deployment_name = "acme-analytics-dev"
  tags            = local.tags

  admin_user_names                 = ["owner@example.com"]
  user_names                       = ["analyst@example.com"]
  service_principal_application_id = var.service_principal_application_id
}

output "workspace_url" {
  description = "The `host` of the workspace stack's databricks provider."
  value       = module.workspace.workspace_url
}

output "workspace_id" {
  description = "For the workspace stack, and for sharing datasets with this workspace."
  value       = module.workspace.workspace_id
}

output "admin_group_name" {
  description = "For the workspace stack's grants."
  value       = module.workspace.admin_group_name
}

output "users_group_name" {
  description = "For the workspace stack's grants, and for sharing datasets with this workspace."
  value       = module.workspace.users_group_name
}

output "metastore_id" {
  description = "For the workspace stack's metastore check."
  value       = data.databricks_metastore.this.metastore_id
}
