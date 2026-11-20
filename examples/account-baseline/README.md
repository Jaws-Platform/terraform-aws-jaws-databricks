# Account baseline (stack 1 of 4)

Applied once per Databricks account, with the **account-level** provider:

- the `us-east-1` Unity Catalog metastore `acme-us-east-1`, with no storage
  root, owned by the group `acme-metastore-admins`;
- delivery of the account's audit logs to the bucket
  `acme-databricks-audit-logs`, under `audit/`;
- the host workspace `acme-shared`: serverless, with no VPC, bucket, catalog
  or users, and no standing cost. Shared datasets are created through it.

Before you apply it, in the Databricks account console: create a service
principal, make it an account admin, and create an OAuth secret for it. Then:

```sh
export DATABRICKS_ACCOUNT_ID=...      # the account ID
export DATABRICKS_CLIENT_ID=...       # the service principal's application ID
export DATABRICKS_CLIENT_SECRET=...   # its OAuth secret

terraform init
terraform plan \
  -var databricks_account_id="$DATABRICKS_ACCOUNT_ID" \
  -var service_principal_application_id="$DATABRICKS_CLIENT_ID"
```

If the account already has a metastore in `us-east-1`, import it or delete it
first: an account has one per region.

Next: [`project-workspace`](https://github.com/Jaws-Platform/terraform-aws-jaws-databricks/tree/main/examples/project-workspace).

In your own configuration, replace the relative `source` with the registry
address:

```hcl
module "databricks" {
  source  = "Jaws-Platform/jaws-databricks/aws"
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
