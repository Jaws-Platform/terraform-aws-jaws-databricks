# databricks-producer-catalog

Part of [`jwallace145/jaws-databricks/aws`](https://registry.terraform.io/modules/jwallace145/jaws-databricks/aws/latest) · [Registry](https://registry.terraform.io/modules/jwallace145/jaws-databricks/aws/latest/submodules/databricks-producer-catalog) · [Source](https://github.com/jwallace145/terraform-aws-jaws-databricks/tree/main/modules/databricks-producer-catalog)

One Unity Catalog catalog per dataset producer, owned by the platform. Every
dataset the producer onboards becomes a schema in it, holding an external
volume `files` (`databricks-dataset`), so a consumer that is granted the
dataset finds it in Catalog Explorer at
`/Volumes/<catalog>/<dataset>/files/`. Applied through the shared-objects host
(`databricks-host-workspace`).

Creates:

- a catalog named after `producer` (`chess-selfplay` gives
  `chess_selfplay`), `ISOLATED`, owned by `owner_group_name`, with its
  managed location at `<storage_url>/<catalog>` (`databricks-catalog-storage`)
  and the property `producer`;
- a read-write binding to the host only.

Consumers are bound read-only, and granted `USE CATALOG`, by
`databricks-producer-catalog-access`, which owns the catalog's grants. The
owner is the platform, never the producer: a catalog's owner can grant anyone
access, which would bypass the producer/consumer handshake.

## Usage

```hcl
# Workspace-level provider on the host: host = databricks-host-workspace's
# workspace_url.
module "chess_selfplay" {
  source  = "jwallace145/jaws-databricks/aws//modules/databricks-producer-catalog"
  version = "0.1.0" # x-release-please-version

  producer          = "chess-selfplay"
  storage_url       = module.dataset_catalogs.url # databricks-catalog-storage
  host_workspace_id = var.host_workspace_id
  owner_group_name  = var.owner_group_name

  # The storage URL is built from a name, so it carries no dependency.
  depends_on = [module.dataset_catalogs]
}
```

The [`dataset-sharing`](https://github.com/jwallace145/terraform-aws-jaws-databricks/tree/main/examples/dataset-sharing)
example shows the whole chain.

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
| [databricks_catalog.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/catalog) | resource |
| [databricks_workspace_binding.host](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/workspace_binding) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| host\_workspace\_id | Numeric ID of the shared-objects host (`databricks-host-workspace`'s `workspace_id`): the workspace this module's `databricks` provider points at, and the only one bound read-write. | `number` | n/a | yes |
| owner\_group\_name | Account group that owns the catalog: the `admin_group_name` output of `databricks-metastore`. Never a producer or consumer group: a catalog's owner can grant anyone access. | `string` | n/a | yes |
| producer | The producing project, in kebab-case, for example `chess-selfplay`. The catalog is named after it, `-` replaced by `_` (`chess_selfplay`). | `string` | n/a | yes |
| storage\_url | The `url` output of `databricks-catalog-storage`, `s3://<bucket>/managed`: the catalog's managed location is `<storage_url>/<catalog>`. | `string` | n/a | yes |
| properties | Extra catalog properties; `producer` is always set to `producer`. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| catalog\_name | The catalog's name: the producer with `-` replaced by `_`. It carries a dependency on the host's binding, so a schema created through the host comes after the binding and is destroyed before it. |
<!-- END_TF_DOCS -->
