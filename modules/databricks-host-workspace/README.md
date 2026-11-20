# databricks-host-workspace

Part of [`Jaws-Platform/jaws-databricks/aws`](https://registry.terraform.io/modules/Jaws-Platform/jaws-databricks/aws/latest) · [Registry](https://registry.terraform.io/modules/Jaws-Platform/jaws-databricks/aws/latest/submodules/databricks-host-workspace) · [Source](https://github.com/Jaws-Platform/terraform-aws-jaws-databricks/tree/main/modules/databricks-host-workspace)

The account's **shared-objects host**: a serverless Databricks workspace that
exists only so that metastore-level objects which must be created through a
workspace, but belong to no project, have a home. Today that is the onboarded
datasets (`databricks-dataset`): their storage credentials and read-only
external locations, and (`databricks-dataset-access`) their bindings to the
consumer workspaces and grants. Applied
once per account, next to `databricks-metastore`, with the account-level
`databricks` provider.

It is deliberately not a project workspace:

| | `databricks-workspace` (a project) | this module |
| --- | --- | --- |
| Customer VPC, subnets, NAT, security group | yes | none (`compute_mode = "SERVERLESS"`) |
| Cross-account role, root bucket | yes | none |
| Catalog, compute policies, users | yes | none |
| Assigned principals | the project's admin and user groups | the metastore admin group only (the automation service principal and the metastore admins), as ADMIN |

So it has no standing AWS cost. Nobody but the metastore admins can sign in,
and nothing in it runs compute, so it incurs no DBUs unless an admin starts
serverless compute by hand.

Creates the workspace (`PREMIUM`, serverless, `custom_tags` = `tags`), its
assignment to the metastore, and the ADMIN assignment of the metastore admin
group (`admin_group_name`, the `admin_group_name` output of
`databricks-metastore`, looked up by name).

## Validation

- `account_id`: a UUID.
- `workspace_name`: kebab-case, at most 30 characters.
- `region`: `us-east-1` only.
- `tags`: must contain `Project`, `Environment`, `CostCenter`, `Workspace`,
  `Owner` and `ManagedBy`, and no key Databricks reserves.

## Known gaps

- Serverless workspaces must be available to the account in us-east-1; the
  apply finds out, not the module.
- An external location created through this workspace can be bound to
  classic workspaces, because bindings are metastore-level.
- Serverless compute cannot be switched off from Terraform here; it is
  contained by assigning nobody but the metastore admins.

## Usage

```hcl
module "host" {
  source  = "Jaws-Platform/jaws-databricks/aws//modules/databricks-host-workspace"
  version = "0.1.2" # x-release-please-version

  workspace_name   = "acme-shared"
  account_id       = var.databricks_account_id
  metastore_id     = module.metastore.metastore_id
  admin_group_name = module.metastore.admin_group_name

  tags = {
    Project     = "data-platform"
    Environment = "prod"
    CostCenter  = "platform"
    Workspace   = "acme-shared"
    Owner       = "platform-team"
    ManagedBy   = "terraform"
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| databricks | >= 1.142, < 2.0 |

## Providers

| Name | Version |
| ---- | ------- |
| databricks | >= 1.142, < 2.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [databricks_metastore_assignment.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/metastore_assignment) | resource |
| [databricks_mws_permission_assignment.admins](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/mws_permission_assignment) | resource |
| [databricks_mws_workspaces.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/mws_workspaces) | resource |
| [databricks_group.admins](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/group) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| account\_id | Databricks account ID (a UUID). | `string` | n/a | yes |
| admin\_group\_name | Account group given ADMIN on the workspace, the `admin_group_name` output of `databricks-metastore`. It holds the automation service principal, which manages the shared objects through the workspace, and the metastore admins. Nobody else is assigned. | `string` | n/a | yes |
| metastore\_id | ID of the region's Unity Catalog metastore, the `metastore_id` output of `databricks-metastore`: the objects created through this workspace live in it. | `string` | n/a | yes |
| tags | Tags on the workspace (`custom_tags`): must contain `Project`, `Environment`, `CostCenter`, `Workspace`, `Owner` and `ManagedBy`, and no key Databricks reserves (`Vendor`, `Creator`, `ClusterName`, `ClusterId`, `Name`). | `map(string)` | n/a | yes |
| workspace\_name | Name of the host workspace, at most 30 characters. One per account. | `string` | n/a | yes |
| region | Region of the workspace. Only `us-east-1` is supported, the metastore's region. | `string` | `"us-east-1"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| workspace\_id | Numeric ID of the host workspace. |
| workspace\_url | URL of the host workspace: the `host` of the workspace-level `databricks` provider that manages shared objects (`databricks-dataset` and `databricks-dataset-access`). |
<!-- END_TF_DOCS -->

