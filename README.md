# terraform-aws-jaws-databricks

[![Terraform Registry](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fregistry.terraform.io%2Fv1%2Fmodules%2Fjaws-platform%2Fjaws-databricks%2Faws&query=%24.version&prefix=v&label=registry&logo=terraform&color=7B42BC)](https://registry.terraform.io/modules/jaws-platform/jaws-databricks/aws/latest)
[![GitHub release](https://img.shields.io/github/v/release/jaws-platform/terraform-aws-jaws-databricks?label=release)](https://github.com/jaws-platform/terraform-aws-jaws-databricks/releases/latest)
[![CI](https://github.com/jaws-platform/terraform-aws-jaws-databricks/actions/workflows/ci.yml/badge.svg?event=pull_request)](https://github.com/jaws-platform/terraform-aws-jaws-databricks/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/jaws-platform/terraform-aws-jaws-databricks/blob/main/LICENSE)

Databricks on AWS with Unity Catalog, as a managed platform: one account
baseline, a workspace per project in its own VPC, a catalog per project that
only Unity Catalog can reach, compute that users can create only through
policies, and S3 datasets shared read-only between projects without copying
them.

The modules are small and follow the line the Databricks provider itself
draws, between the account-level API and a workspace's API. Each one states
what it creates, what it deliberately does not, and its known gaps. It is one
of the [Jaws](https://github.com/jwallace145/jaws) module families, and has no
dependency on Jaws: everything is a plain input.

## What it creates

```text
 Databricks account                                  AWS account
 ──────────────────                                  ───────────
 ┌─ 1. account baseline · once ───────────────────────────────────────────────┐
 │  Unity Catalog metastore (no storage root)   audit log bucket              │
 │  metastore admin group                       log delivery role             │
 │  host workspace (serverless: no VPC, no bucket, no users, no standing cost)│
 └────────────────────────────────────────────────────────────────────────────┘
 ┌─ 2. account stack · once per project ──────────────────────────────────────┐
 │  workspace <project>-<environment>           VPC, private subnets, NAT *   │
 │  admin and users groups                      security group                │
 │  metastore assignment                        root bucket                   │
 │  optional deployer (GitHub OIDC, no secret)  cross-account role            │
 └────────────────────────────────────────────────────────────────────────────┘
 ┌─ 3. workspace stack · once per project, after its account stack ───────────┐
 │  catalog <project>, bound to the workspace   catalog bucket, readable and  │
 │  storage credential, external location       writable only as the Unity    │
 │  grants for the admin and users groups       Catalog role                  │
 │  compute policies with pinned tags           Unity Catalog role            │
 │  entitlements and workspace settings                                       │
 └────────────────────────────────────────────────────────────────────────────┘
 ┌─ 4. shared datasets · through the host workspace ──────────────────────────┐
 │  a catalog per producer                      managed-storage bucket        │
 │  per dataset: read-only credential,          per dataset: a role that can  │
 │  external location, schema, volume `files`   read only once the dataset's  │
 │  per consumer: workspace bindings and        own bucket policy names it    │
 │  grants, in authoritative sets                                             │
 └────────────────────────────────────────────────────────────────────────────┘

 * from the network family, jaws-platform/jaws-network/aws
```

## Four stacks, in order

A Terraform provider has to be configured before anything is planned, and a
workspace-level `databricks` provider needs the URL of a workspace that the
account-level provider creates. So this is four stacks rather than one, each
applied with the outputs of the one before:

| | Stack | `databricks` provider | Modules | Applied |
|---|---|---|---|---|
| 1 | Account baseline | account (`https://accounts.cloud.databricks.com`) | the root module: `databricks-metastore`, `databricks-audit-logs`, `databricks-host-workspace` | once per account |
| 2 | Account stack | account | `databricks-workspace`, with a VPC and NAT | once per project |
| 3 | Workspace stack | the project's workspace (`workspace_url` of stack 2) | `databricks-catalog`, `databricks-workspace-config` | once per project, after stack 2 |
| 4 | Shared datasets | the host workspace (`host_workspace_url` of stack 1) | `databricks-catalog-storage`, `databricks-producer-catalog`, `databricks-dataset`, `databricks-dataset-access`, `databricks-producer-catalog-access` | when a dataset is shared |

One service principal runs all four. The baseline puts it in the metastore
admin group, which is the host's only admin, and each account stack makes it
an admin of its workspace. The modules never configure a provider and never
take a secret: authentication comes from the environment
(`DATABRICKS_ACCOUNT_ID`, `DATABRICKS_CLIENT_ID`, `DATABRICKS_CLIENT_SECRET`).

## Modules

**Account level**

| Module | Creates |
|---|---|
| [root](https://registry.terraform.io/modules/jaws-platform/jaws-databricks/aws/latest) | The account baseline in one call: the three modules below, with every name derived from `name_root`. |
| [`databricks-metastore`](https://registry.terraform.io/modules/jaws-platform/jaws-databricks/aws/latest/submodules/databricks-metastore) | The region's Unity Catalog metastore, with no storage root, owned by an admin group that holds the named users and the automation service principal. |
| [`databricks-audit-logs`](https://registry.terraform.io/modules/jaws-platform/jaws-databricks/aws/latest/submodules/databricks-audit-logs) | A private, versioned S3 bucket, a role that trusts Databricks' log delivery role with the account ID as external ID, and audit log delivery (JSON) under one prefix. |
| [`databricks-host-workspace`](https://registry.terraform.io/modules/jaws-platform/jaws-databricks/aws/latest/submodules/databricks-host-workspace) | A serverless workspace with no VPC, NAT, bucket, catalog or users, assigned to the metastore with only the metastore admin group as admin, so that objects no project owns have a workspace to be created through. |
| [`databricks-workspace`](https://registry.terraform.io/modules/jaws-platform/jaws-databricks/aws/latest/submodules/databricks-workspace) | A PREMIUM workspace in a customer-managed VPC: security group with Databricks' documented egress ports, network configuration, root bucket, cross-account role, metastore assignment, admin and users groups, an optional secretless deployer for GitHub Actions, and the S3 endpoint policy for its VPC. |

**Workspace level**

| Module | Creates |
|---|---|
| [`databricks-catalog`](https://registry.terraform.io/modules/jaws-platform/jaws-databricks/aws/latest/submodules/databricks-catalog) | The project's isolated catalog on managed storage in a bucket whose policy denies object access to everyone but the Unity Catalog role, with that role, the storage credential, the external location, workspace bindings and grants for the admin and users groups. |
| [`databricks-workspace-config`](https://registry.terraform.io/modules/jaws-platform/jaws-databricks/aws/latest/submodules/databricks-workspace-config) | Cluster policies with the governance tags pinned as fixed rules and auto-termination required, `CAN_USE` for the users group, cluster creation switched off outside policies, and workspace settings (legacy DBFS and legacy access off, a token lifetime cap). |

**Shared datasets, through the host workspace**

| Module | Creates |
|---|---|
| [`databricks-catalog-storage`](https://registry.terraform.io/modules/jaws-platform/jaws-databricks/aws/latest/submodules/databricks-catalog-storage) | Managed storage for the producer catalogs: a bucket only its Unity Catalog role can read or write, the role, and an isolated storage credential and external location bound to the host. Nothing is written there. |
| [`databricks-producer-catalog`](https://registry.terraform.io/modules/jaws-platform/jaws-databricks/aws/latest/submodules/databricks-producer-catalog) | One isolated catalog per dataset producer, owned by the platform and bound read-write to the host only. Each dataset the producer shares is a schema in it. |
| [`databricks-dataset`](https://registry.terraform.io/modules/jaws-platform/jaws-databricks/aws/latest/submodules/databricks-dataset) | One S3 dataset onboarded once: a role with no read permission of its own, a read-only storage credential and external location, and a schema holding the external volume `files`. It grants nothing. |
| [`databricks-dataset-access`](https://registry.terraform.io/modules/jaws-platform/jaws-databricks/aws/latest/submodules/databricks-dataset-access) | Who may read one dataset: per consumer, bindings of the location and credential to its workspace, and `USE_SCHEMA` and `READ_VOLUME` for its users group, in authoritative grant sets. |
| [`databricks-producer-catalog-access`](https://registry.terraform.io/modules/jaws-platform/jaws-databricks/aws/latest/submodules/databricks-producer-catalog-access) | Who may see one producer catalog: per consumer, a read-only binding to its workspace and `USE_CATALOG` for its users group, in an authoritative grant set. |

## Usage

The account baseline, applied once:

```hcl
provider "databricks" {
  host = "https://accounts.cloud.databricks.com"
}

module "databricks" {
  source  = "jaws-platform/jaws-databricks/aws"
  version = "0.1.1" # x-release-please-version

  account_id = var.databricks_account_id
  name_root  = "acme"

  admin_user_names                 = ["owner@example.com"]
  service_principal_application_id = var.service_principal_application_id

  tags = {
    Project     = "data-platform"
    Environment = "prod"
    CostCenter  = "platform"
    Owner       = "platform-team"
    ManagedBy   = "terraform"
  }
}
```

A project's workspace, in its own stack. The network comes from
[`jaws-platform/jaws-network/aws`](https://registry.terraform.io/modules/jaws-platform/jaws-network/aws/latest),
and the S3 endpoint policy the workspace module builds is what keeps the
catalog bucket reachable only through Unity Catalog:

```hcl
module "network" {
  source  = "jaws-platform/jaws-network/aws"
  version = "~> 0.1"

  name                 = "acme-analytics"
  private_subnet_cidrs = ["10.0.128.0/20", "10.0.144.0/20"]

  s3_gateway_endpoint = { enabled = true, policy = module.workspace.s3_endpoint_policy }
  nat                 = { ami_id = data.aws_ami.nat.id }
}

module "workspace" {
  source  = "jaws-platform/jaws-databricks/aws//modules/databricks-workspace"
  version = "0.1.1" # x-release-please-version

  account_id   = var.databricks_account_id
  name_root    = "acme"
  project      = "analytics"
  environment  = "dev"
  vpc_id       = module.network.vpc_id
  subnet_ids   = module.network.private_subnet_ids
  metastore_id = data.databricks_metastore.this.metastore_id
  tags         = local.tags # Project, Environment, CostCenter, Workspace, Owner, ManagedBy

  admin_user_names                 = ["owner@example.com"]
  user_names                       = ["analyst@example.com"]
  service_principal_application_id = var.service_principal_application_id
}
```

Then the workspace stack, whose provider points at the workspace that was
just created:

```hcl
provider "databricks" {
  host = var.workspace_url # the account stack's workspace_url output
}

module "catalog" {
  source  = "jaws-platform/jaws-databricks/aws//modules/databricks-catalog"
  version = "0.1.1" # x-release-please-version

  name_root        = "acme"
  project          = "analytics"
  workspace_id     = var.workspace_id
  admin_group_name = var.admin_group_name
  users_group_name = var.users_group_name
  apply_role_arn   = var.apply_role_arn
  tags             = local.tags
}
```

## Examples

One per stack, in the order they are applied:

1. [`account-baseline`](https://github.com/jaws-platform/terraform-aws-jaws-databricks/tree/main/examples/account-baseline):
   the metastore, audit logs and the host workspace.
2. [`project-workspace`](https://github.com/jaws-platform/terraform-aws-jaws-databricks/tree/main/examples/project-workspace):
   a VPC with a NAT instance and a workspace in it.
3. [`workspace-catalog`](https://github.com/jaws-platform/terraform-aws-jaws-databricks/tree/main/examples/workspace-catalog):
   the project's catalog, compute policies and workspace settings.
4. [`dataset-sharing`](https://github.com/jaws-platform/terraform-aws-jaws-databricks/tree/main/examples/dataset-sharing):
   one S3 dataset made readable from another project's workspace.

## How access is contained

- **Data is reachable only through Unity Catalog.** A catalog bucket's policy
  denies object reads and writes to every principal but the Unity Catalog
  role, whatever IAM allows them, and the workspace VPC's S3 endpoint admits
  that bucket only as that role, so credentials pasted into a notebook cannot
  read around the catalog.
- **Groups own things, not people.** The metastore, the catalogs and every
  shared object are owned by groups that also hold the automation service
  principal, so control survives a person leaving.
- **No storage at the metastore level.** The metastore has no storage root:
  each catalog has its own bucket and credential, and nothing is shared
  between projects by accident.
- **Users create compute only through policies**, every cluster carries the
  governance tags as fixed rules, and none runs without auto-termination.
- **Sharing a dataset takes three separate agreements**: the platform
  onboards it and binds the consumer, the producer's bucket policy names the
  dataset's role, and the consumer's S3 endpoint lets that role through.
  Onboarding alone grants nothing.
- **Grants are authoritative.** Each grant set is one `databricks_grants`
  that always holds the owner group, so a grant made by hand is removed at the
  next apply. Bindings are created last and destroyed first, so a run that
  stops half way leaves less access, never more.
- **No long-lived secret in CI.** The optional deployer is a service
  principal that GitHub Actions signs in as through OIDC federation, scoped to
  one repository's `prod` environment.

## Cost

| | Standing cost |
|---|---|
| Metastore, groups, catalogs, policies, grants, bindings | none |
| Host workspace | none: serverless, and nobody but the metastore admins can sign in |
| Audit log, root, catalog and managed-storage buckets | S3 storage for what is written |
| A project workspace's network | the NAT instance, about $7 a month with [`nat-instance`](https://registry.terraform.io/modules/jaws-platform/jaws-network/aws/latest/submodules/nat-instance) |
| Compute | Databricks DBUs and EC2, only while clusters or serverless compute run |

## What to know before using it

- **`us-east-1` only.** The modules validate the region, and the workspace's
  S3 endpoint policy names the Databricks-owned `us-east-1` buckets.
- **One metastore per region per account.** If the account already has one in
  `us-east-1`, import it into `databricks-metastore` or delete it first;
  creating a second fails.
- **Workspaces are PREMIUM**, which Unity Catalog needs.
- **Serverless compute is not governed.** It stays enabled, it is not covered
  by the compute policies, and it does not go through the VPC's S3 endpoint.
- **IAM is eventually consistent.** The modules wait where Databricks
  validates a new role, but if a first apply still fails on a role it just
  created, apply again.
- **Destroy a project in reverse order**: empty the catalog bucket, destroy
  the workspace stack, then the account stack.
  [`databricks-catalog`](https://registry.terraform.io/modules/jaws-platform/jaws-databricks/aws/latest/submodules/databricks-catalog)
  explains why the bucket is emptied first.
- **The users and the service principal must already exist** in the
  Databricks account; the modules look them up, they do not create them.
- **Tags.** AWS resources get `Component` and `Name` from the module and
  everything else from the caller's provider `default_tags`. Databricks does
  not see those, so workspaces, clusters and catalogs take a `tags` input
  that must contain `Project`, `Environment`, `CostCenter`, `Workspace`,
  `Owner` and `ManagedBy`.

Each submodule's README has its own validation rules and known gaps.

## Requirements

| | Version |
|---|---|
| Terraform | `>= 1.11` |
| [`hashicorp/aws`](https://registry.terraform.io/providers/hashicorp/aws/latest) | `~> 6.0` |
| [`databricks/databricks`](https://registry.terraform.io/providers/databricks/databricks/latest) | `>= 1.142, < 2.0` |

## Development

See [CONTRIBUTING.md](https://github.com/jaws-platform/terraform-aws-jaws-databricks/blob/main/CONTRIBUTING.md)
for local setup, the commit and pull request rules, CI, and how releases work.
`scripts/check.sh` runs everything CI runs against mocked providers, with no
AWS or Databricks credentials.

## Root module reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| aws | ~> 6.0 |
| databricks | >= 1.142, < 2.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| audit\_logs | ./modules/databricks-audit-logs | n/a |
| host\_workspace | ./modules/databricks-host-workspace | n/a |
| metastore | ./modules/databricks-metastore | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| account\_id | Databricks account ID (a UUID). It is also the external ID the audit log delivery role requires from Databricks. | `string` | n/a | yes |
| admin\_user\_names | Databricks user names (email addresses) of the people who administer the metastore, for example `["owner@example.com"]`. Each user must already exist in the account. | `list(string)` | n/a | yes |
| name\_root | Prefix of every name this module derives, in kebab-case, for example `acme`: the metastore `<name_root>-us-east-1`, its admin group `<name_root>-metastore-admins`, the audit log bucket `<name_root>-databricks-audit-logs`, the log delivery role `<name_root>-databricks-log-delivery` and the host workspace `<name_root>-shared`. Each can be set on its own instead. | `string` | n/a | yes |
| service\_principal\_application\_id | Application (client) ID of the account-level service principal that automation authenticates as. It joins the metastore admin group, so automation keeps control of the metastore, and it becomes an admin of the host workspace. | `string` | n/a | yes |
| admin\_group\_name | Name of the account-level group that owns the metastore. Null names it `<name_root>-metastore-admins`. | `string` | `null` | no |
| audit\_logs | Delivery of the account's audit logs (JSON) to a private, versioned S3 bucket. `bucket_name` and `role_name` default to `<name_root>-databricks-audit-logs` and `<name_root>-databricks-log-delivery`; Databricks may write under `<prefix>/` only. Set `enabled = false` to skip it, for example when another stack already delivers the account's audit logs. | <pre>object({<br/>    enabled     = optional(bool, true)<br/>    bucket_name = optional(string)<br/>    role_name   = optional(string)<br/>    prefix      = optional(string, "audit")<br/>  })</pre> | `{}` | no |
| host\_workspace | The shared-objects host: a serverless workspace with no VPC, NAT, bucket, catalog or users, through which metastore-level objects that belong to no project (shared datasets) are created. `name` defaults to `<name_root>-shared` (at most 30 characters). Set `enabled = false` if nothing will be shared across workspaces. | <pre>object({<br/>    enabled = optional(bool, true)<br/>    name    = optional(string)<br/>  })</pre> | `{}` | no |
| metastore\_name | Name of the Unity Catalog metastore. Null names it `<name_root>-us-east-1`. An account has one metastore per region, shared by every workspace there. | `string` | `null` | no |
| tags | Tags on the host workspace (`custom_tags`): must contain `Project`, `Environment`, `CostCenter`, `Owner` and `ManagedBy`, and no key Databricks reserves (`Vendor`, `Creator`, `ClusterName`, `ClusterId`, `Name`). `Workspace` defaults to the host workspace's name. Not needed when `host_workspace.enabled` is false; AWS resources take their tags from the provider's `default_tags`. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| admin\_group\_name | Name of the account group that owns the metastore: the `owner_group_name` input of the dataset modules. |
| audit\_log\_bucket\_arn | ARN of the audit log bucket, for the IAM policies of principals that share it under another prefix. Null when `audit_logs.enabled` is false. |
| audit\_log\_bucket\_name | Name of the audit log bucket. Null when `audit_logs.enabled` is false. |
| host\_workspace\_id | Numeric ID of the host workspace: the `host_workspace_id` input of the dataset modules. Null when `host_workspace.enabled` is false. |
| host\_workspace\_url | URL of the host workspace: the `host` of the workspace-level `databricks` provider that the dataset modules are applied through. Null when `host_workspace.enabled` is false. |
| log\_delivery\_config\_id | ID of the Databricks audit log delivery configuration. Null when `audit_logs.enabled` is false. |
| metastore\_id | ID of the Unity Catalog metastore: the `metastore_id` input of `databricks-workspace` and `databricks-workspace-config`. |
| metastore\_name | Name of the metastore, for stacks that look it up with the `databricks_metastore` data source instead of taking its ID. |
<!-- END_TF_DOCS -->

## License

[MIT](https://github.com/jaws-platform/terraform-aws-jaws-databricks/blob/main/LICENSE)
