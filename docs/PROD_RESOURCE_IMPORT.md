# Production Resource Import Guide

## Problem

When running `terraform apply` for production, you may encounter errors like:

```
Error: creating IAM Role (***): EntityAlreadyExists: Role with name *** already exists.
Error: creating ECR Repository: RepositoryAlreadyExistsException: The repository already exists
Error: creating RDS DB Subnet Group: DBSubnetGroupAlreadyExists: The DB subnet group already exists
Error: creating AWS DynamoDB Table: ResourceInUseException: Table already exists
```

This happens when resources exist in AWS but are not in Terraform state.

## Solution

Import all existing resources into Terraform state before running `terraform apply`.

## Quick Solution: Use the Import Script

Run the automated import script:

```bash
cd /path/to/shelf-shack-infra
./scripts/import-prod-resources.sh
```

This script will automatically import:
- IAM Roles (deploy role, OpenSearch EC2 role, WebSocket Lambda role)
- ECR Repository
- RDS DB Subnet Group
- DynamoDB Table

## Manual Import (Alternative)

If you prefer to import manually or the script doesn't work, use these commands:

```bash
cd envs/prod
terraform init

# 1. Import Deploy Role
terraform import aws_iam_role.deploy_role shelfshackDeployRole

# 2. Import ECR Repository
terraform import module.ecr.aws_ecr_repository.this shelfshack-prod-repo

# 3. Import OpenSearch EC2 IAM Role
terraform import 'module.opensearch_ec2[0].aws_iam_role.opensearch' shelfshack-prod-opensearch-ec2-role

# 4. Import RDS DB Subnet Group
terraform import module.rds.aws_db_subnet_group.this shelfshack-prod-db-subnets

# 5. Import DynamoDB Table
terraform import module.websocket_lambda.aws_dynamodb_table.websocket_connections shelfshack-prod-websocket-connections

# 6. Import WebSocket Lambda IAM Role
terraform import module.websocket_lambda.aws_iam_role.lambda_role shelfshack-prod-websocket-lambda-role
```

## Additional Resources That May Need Import

After importing the above, you may also need to import:

### IAM Role Policies

```bash
# Deploy Role Policy
terraform import aws_iam_role_policy.deploy_role_consolidated shelfshackDeployRole:shelfshackDeployRole-consolidated-policy

# OpenSearch EC2 Role Policy (if exists)
terraform import 'module.opensearch_ec2[0].aws_iam_role_policy.opensearch[0]' shelfshack-prod-opensearch-ec2-role:opensearch-policy

# WebSocket Lambda Role Policies (if they exist as separate resources)
terraform import 'module.websocket_lambda.aws_iam_role_policy.lambda_policy' shelfshack-prod-websocket-lambda-role:lambda-policy
```

### Other Resources

If you have other resources that were created manually, check what's in your AWS account and import them:

```bash
# List all resources in state
terraform state list

# Check what resources Terraform wants to create
terraform plan
```

## CI/CD Integration

For CI/CD, add an import step before `terraform apply`:

```yaml
- name: Import existing resources
  working-directory: envs/prod
  run: |
    terraform init -backend-config=backend.tf || true
    # Import resources that may already exist
    terraform import aws_iam_role.deploy_role shelfshackDeployRole || true
    terraform import module.ecr.aws_ecr_repository.this shelfshack-prod-repo || true
    terraform import 'module.opensearch_ec2[0].aws_iam_role.opensearch' shelfshack-prod-opensearch-ec2-role || true
    terraform import module.rds.aws_db_subnet_group.this shelfshack-prod-db-subnets || true
    terraform import module.websocket_lambda.aws_dynamodb_table.websocket_connections shelfshack-prod-websocket-connections || true
    terraform import module.websocket_lambda.aws_iam_role.lambda_role shelfshack-prod-websocket-lambda-role || true
  continue-on-error: true
```

Or use the import script:

```yaml
- name: Import existing resources
  run: |
    cd shelf-shack-infra
    chmod +x scripts/import-prod-resources.sh
    ./scripts/import-prod-resources.sh || true
  continue-on-error: true
```

## Verification

After importing, verify everything is correct:

```bash
# Check what's in state
terraform state list

# Run a plan to see what Terraform wants to change
terraform plan

# If everything looks good, apply
terraform apply
```

## Troubleshooting

### Error: "Resource already managed by Terraform"
This means the resource is already in state. The import will be skipped. This is safe to ignore.

### Error: "Resource not found"
This means the resource doesn't exist in AWS. Terraform will create it on apply. This is expected.

### Error: "Invalid resource ID format"
Some resources require specific ID formats. Check the Terraform AWS provider documentation for the correct format.

### Import succeeds but plan shows changes
This is normal - Terraform may want to update tags, policies, or other attributes to match your configuration. Review the plan carefully before applying.

## Notes

- Imports only need to happen **once** per resource. After that, Terraform manages them.
- Always run `terraform plan` after importing to verify the state matches your configuration.
- Some resources (like IAM role policies) may be managed as part of the role resource, so separate imports may not be needed.

