# Sharing an S3 dataset between projects (stack 4 of 4)

Makes one S3 dataset readable, read-only and without a copy, from another
project's workspace. Applied with a **workspace-level** provider whose `host`
is the host workspace's URL (the account baseline's `host_workspace_url`
output), because the objects involved belong to no project.

| | In this example |
|---|---|
| Producer | `chess-selfplay`, which owns the bucket `acme-chess-selfplay-positions` |
| Dataset | `positions`, at `s3://acme-chess-selfplay-positions/data/` |
| Consumer | the `analytics` workspace |
| Where the consumer reads it | `/Volumes/chess_selfplay/positions/files/` |

What it creates:

1. `databricks-catalog-storage`: one bucket of managed storage for all
   producer catalogs. Nothing is written to it.
2. `databricks-producer-catalog`: the catalog `chess_selfplay`, owned by the
   platform rather than the producer.
3. `databricks-dataset`: the dataset, onboarded once. A role, a read-only
   storage credential and external location, and the schema `positions`
   holding the external volume `files`.
4. `databricks-producer-catalog-access` and `databricks-dataset-access`: the
   consumer's workspace bindings and its users group's grants.

**This stack alone does not open the data.** Two more things have to agree,
each in the stack of the project that owns it:

- the **producer** names `dataset_role_arn` as a reader in the bucket's own
  policy (with
  [`dataset-bucket`](https://registry.terraform.io/modules/Jaws-Platform/jaws-research/aws/latest/submodules/dataset-bucket),
  its `reader_role_arns`);
- the **consumer** adds `endpoint_dataset` to its workspace's
  `read_only_datasets`, so its VPC's S3 endpoint lets that role through.

Until both are in place, reads fail with access denied and nothing else
changes. Removing a consumer from `consumers` removes its bindings first and
its grants second.

```sh
terraform init
terraform plan -var host_workspace_url=... -var host_workspace_id=... # and the rest
```

In your own configuration, replace the relative `source` with the registry
address, for example:

```hcl
module "positions" {
  source  = "Jaws-Platform/jaws-databricks/aws//modules/databricks-dataset"
  version = "0.1.1" # x-release-please-version
  # ...
}
```
