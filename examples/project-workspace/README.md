# Project workspace (stack 2 of 4)

Applied once per project, with the **account-level** provider. This is the
project's *account stack*:

- a VPC with two private `/20` subnets, a `t4g.nano` NAT instance for their
  egress and an S3 gateway endpoint, from
  [`jaws-platform/jaws-network/aws`](https://registry.terraform.io/modules/jaws-platform/jaws-network/aws/latest);
- the workspace `analytics-dev` in that VPC, with its security group, root
  bucket and cross-account role, assigned to the account's metastore;
- the groups `analytics-workspace-admins` and `analytics-workspace-users`.

Two things in it are worth a second look:

- **The S3 endpoint policy comes from the workspace module.** It admits the
  Databricks-owned buckets the compute plane needs, the root bucket, and the
  catalog bucket only as the Unity Catalog role. The policy is built from
  names alone, so the network taking it from the workspace, while the
  workspace takes its subnets from the network, is not a cycle.
- **The metastore is looked up by name**, so this stack and the account
  baseline share no state.

The NAT instance is the only standing cost here, about $7 a month. Clusters
cost money only while they run.

```sh
terraform init
terraform plan \
  -var databricks_account_id="$DATABRICKS_ACCOUNT_ID" \
  -var service_principal_application_id="$DATABRICKS_CLIENT_ID"
```

Its outputs are the inputs of the next stack,
[`workspace-catalog`](https://github.com/jaws-platform/terraform-aws-jaws-databricks/tree/main/examples/workspace-catalog).

In your own configuration, replace the relative and git sources with the
registry addresses:

```hcl
module "network" {
  source  = "jaws-platform/jaws-network/aws"
  version = "~> 0.1"
  # ...
}

module "workspace" {
  source  = "jaws-platform/jaws-databricks/aws//modules/databricks-workspace"
  version = "0.1.0" # x-release-please-version
  # ...
}
```
