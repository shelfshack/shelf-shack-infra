# Terraform Destroy Guide

## Overview

The Terraform configuration includes resource protection to prevent accidental destruction during normal applies. However, when you need to explicitly destroy resources, you can control this behavior.

## Resource Protection

Critical resources have `prevent_destroy = true` by default to prevent accidental deletion during `terraform apply`. These resources include:

- **API Gateway (HTTP & WebSocket)**: Prevents accidental API deletion
- **IAM Deploy Role**: Prevents deletion of deployment role
- **Route53 Records**: Prevents DNS record deletion

## How to Destroy Resources

### Option 1: Set Variable in terraform.tfvars (Recommended)

Edit `envs/prod/terraform.tfvars` or `envs/dev/terraform.tfvars`:

```hcl
# Set to false to allow resource destruction
prevent_resource_destruction = false
```

Then run:
```bash
cd envs/prod  # or envs/dev
terraform destroy
```

**Important**: After setting to `false`, you must run `terraform apply` first to update the protection resource, then you can destroy. Or use Option 2 below.

After destruction, you can set it back to `true` for future applies.

### Option 2: Override via Command Line (Easiest)

This is the easiest method - no need to edit files:

```bash
cd envs/prod
terraform destroy -var="prevent_resource_destruction=false"
```

This works immediately without needing to apply first.

### Option 2: Override via Command Line

```bash
cd envs/prod
terraform destroy -var="prevent_resource_destruction=false"
```

### Option 3: Use Environment Variable

```bash
export TF_VAR_prevent_resource_destruction=false
cd envs/prod
terraform destroy
```

## Destroy Workflow

### Step 1: Disable Resource Protection

```bash
# Edit terraform.tfvars
prevent_resource_destruction = false
```

### Step 2: Review Destroy Plan

```bash
terraform plan -destroy
```

This shows what will be destroyed without actually destroying it.

### Step 3: Execute Destroy

```bash
terraform destroy
```

### Step 4: Re-enable Protection (Optional)

After destruction, if you plan to recreate resources, set it back:

```hcl
prevent_resource_destruction = true
```

## Destroy Order

Terraform automatically handles dependencies and destroys resources in the correct order:

1. **Dependent Resources First**:
   - API Gateway routes and integrations
   - ECS services
   - Lambda functions
   - Security group rules

2. **Core Resources**:
   - API Gateways
   - Load Balancers
   - ECS Clusters
   - RDS Instances

3. **Networking**:
   - Subnets
   - Route Tables
   - Internet Gateways
   - VPC

4. **IAM and Final Resources**:
   - IAM Roles and Policies
   - CloudWatch Log Groups

## Important Notes

### RDS Snapshots

If `db_skip_final_snapshot = false`, Terraform will create a final snapshot before destroying the RDS instance. Ensure you have sufficient storage and permissions.

### ECR Images

ECR repositories are configured with `force_delete = true`, so images will be deleted along with the repository.

### State File

After destruction, your Terraform state file will be empty (or contain only backend configuration). You can:

- Keep the state file for reference
- Delete it if you're completely removing the infrastructure
- Use it to track what was destroyed

## Troubleshooting

### Error: "Instance cannot be destroyed"

If you see this error, it means `prevent_resource_destruction = true` is still set. 

**Solution**: Set `prevent_resource_destruction = false` in `terraform.tfvars` or via command line.

### Error: "Dependency violation"

Some resources may have dependencies that prevent destruction. Terraform will show which resources are blocking destruction.

**Solution**: Review the error message and destroy blocking resources first, or use `-target` to destroy specific resources.

### Error: "RDS deletion protection"

If RDS has `deletion_protection = true`, you need to disable it first.

**Solution**: Set `db_deletion_protection = false` in `terraform.tfvars` and apply, then destroy.

## Best Practices

1. **Always Review Plan**: Run `terraform plan -destroy` before executing `terraform destroy`
2. **Backup Critical Data**: Ensure RDS snapshots and ECR images are backed up if needed
3. **Use Workspaces**: Consider using Terraform workspaces to isolate environments
4. **Document Dependencies**: Keep track of external dependencies (Route53 zones, ACM certificates)
5. **Re-enable Protection**: After recreating infrastructure, set `prevent_resource_destruction = true`

## Example: Complete Destroy and Recreate

```bash
# 1. Disable protection
echo 'prevent_resource_destruction = false' >> envs/prod/terraform.tfvars

# 2. Review what will be destroyed
cd envs/prod
terraform plan -destroy

# 3. Destroy everything
terraform destroy -auto-approve

# 4. Re-enable protection for future
sed -i '' 's/prevent_resource_destruction = false/prevent_resource_destruction = true/' terraform.tfvars

# 5. Recreate infrastructure
terraform apply -var-file=terraform.tfvars
```

## Safety Features

- **Default Protection**: Resources are protected by default (`prevent_resource_destruction = true`)
- **Explicit Override**: Must explicitly set to `false` to allow destruction
- **Clear Documentation**: Variable descriptions explain the purpose
- **Idempotent Applies**: Normal applies won't accidentally destroy resources
