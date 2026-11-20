# Workspace catalog and compute policies (stack 3 of 4)

Applied once per project, after its account stack, with a **workspace-level**
provider whose `host` is that stack's `workspace_url` output. This is the
project's *workspace stack*:

- the catalog `analytics`, bound to this workspace only, on managed storage
  in the bucket `acme-analytics-databricks-catalog`. The bucket's policy
  denies object reads and writes to every principal but the Unity Catalog
  role, so the data is reachable only through Unity Catalog;
- grants: everything for the admin group; using the catalog, creating schemas
  and tables, and reading and modifying data for the users group;
- two compute policies. Users cannot create a cluster outside a policy, every
  cluster created through one carries the governance tags, and each policy
  sets `autotermination_minutes`;
- workspace settings: legacy DBFS and legacy access off, personal access
  tokens capped at 90 days.

It is a separate stack because its provider needs the workspace to exist
first. Pass the account stack's outputs as variables:

```sh
terraform init
terraform plan \
  -var workspace_url="https://acme-analytics-dev.cloud.databricks.com" \
  -var workspace_id=1234567890123456 \
  -var admin_group_name=analytics-workspace-admins \
  -var users_group_name=analytics-workspace-users \
  -var metastore_id=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee \
  -var apply_role_arn=arn:aws:iam::111122223333:role/acme-analytics-ci-apply
```

To destroy a project, empty the catalog bucket first, then destroy this stack,
then the account stack.

In your own configuration, replace the relative `source` with the registry
address:

```hcl
module "catalog" {
  source  = "jaws-platform/jaws-databricks/aws//modules/databricks-catalog"
  version = "0.1.0" # x-release-please-version
  # ...
}

module "workspace_config" {
  source  = "jaws-platform/jaws-databricks/aws//modules/databricks-workspace-config"
  version = "0.1.0" # x-release-please-version
  # ...
}
```
