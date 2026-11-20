# databricks-metastore

Part of [`jaws-platform/jaws-databricks/aws`](https://registry.terraform.io/modules/jaws-platform/jaws-databricks/aws/latest) · [Registry](https://registry.terraform.io/modules/jaws-platform/jaws-databricks/aws/latest/submodules/databricks-metastore) · [Source](https://github.com/jaws-platform/terraform-aws-jaws-databricks/tree/main/modules/databricks-metastore)

The Unity Catalog metastore for the Databricks account, and the admin group
that owns it. There is **one metastore per region per account**, and every
workspace in that region is assigned to it, so this module is instantiated
once per account, never per project.

The metastore has **no `storage_root`**: each project's catalog gets its own
managed location (its own bucket), so nothing is written to a metastore-level
bucket and no credential has to be shared across projects.

The owner is the admin group (`admin_group_name`), not a person. The group
holds the users in `admin_user_names` (looked up by user name, which is their
email address; they must already exist in the account) and the automation
service principal (looked up by `service_principal_application_id`), so
automation keeps control after a person leaves.

The module uses an **account-level** `databricks` provider
(`host = "https://accounts.cloud.databricks.com"`, authentication from the
environment) and never configures it.

**Adopting or deleting an existing metastore.** A Databricks account may
already have an auto-created metastore in `us-east-1`; creating a second one
fails. Either import it into this module or delete it first; the module does
not decide for you. Deleting a metastore detaches every
workspace from it.

No `Resource = "*"` policies are created here.

## Usage

```hcl
provider "databricks" {
  host = "https://accounts.cloud.databricks.com"
}

module "metastore" {
  source  = "jaws-platform/jaws-databricks/aws//modules/databricks-metastore"
  version = "0.1.0" # x-release-please-version

  name                             = "acme-us-east-1"
  admin_group_name                 = "acme-metastore-admins"
  admin_user_names                 = ["owner@example.com"]
  service_principal_application_id = "00000000-0000-0000-0000-000000000000"
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
| [databricks_group.admins](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/group) | resource |
| [databricks_group_member.service_principal](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/group_member) | resource |
| [databricks_group_member.users](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/group_member) | resource |
| [databricks_metastore.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/metastore) | resource |
| [databricks_service_principal.automation](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/service_principal) | data source |
| [databricks_user.admins](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/user) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| admin\_group\_name | Account-level group that owns the metastore. | `string` | n/a | yes |
| admin\_user\_names | Databricks user names (email addresses) of the people who administer the metastore, for example `["owner@example.com"]`. Each user must already exist in the account. | `list(string)` | n/a | yes |
| name | Name of the metastore. There is one metastore per region per Databricks account, shared by every workspace in that region. | `string` | n/a | yes |
| service\_principal\_application\_id | Application (client) ID of the account-level service principal that automation authenticates as. It joins the admin group, so automation keeps control of the metastore. | `string` | n/a | yes |
| region | Region of the metastore. Only `us-east-1` is supported: every workspace of the account lives there. | `string` | `"us-east-1"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| admin\_group\_name | Name of the group that owns the metastore. |
| metastore\_id | ID of the metastore, for `databricks_metastore_assignment` in each workspace stack. |
<!-- END_TF_DOCS -->
