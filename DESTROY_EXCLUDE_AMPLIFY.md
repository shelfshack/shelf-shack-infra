# Destroy Everything Except Amplify Branch

To destroy all resources while keeping the Amplify branch (works for both **dev** and **prod**):

## Option 1: Using the Script

```bash
# Dev – interactive
./scripts/destroy.sh dev

# Dev – auto-approve
./scripts/destroy.sh dev --auto-approve

# Prod – interactive
./scripts/destroy.sh prod

# Prod – auto-approve
./scripts/destroy.sh prod --auto-approve
```

The script removes the Amplify branch from Terraform state before destroying (if present), so the branch stays in AWS.

## Option 2: Manual Commands

**Dev:**

```bash
cd envs/dev
terraform state rm aws_amplify_branch.development[0]   # if present
terraform destroy -var-file=terraform.tfvars
# or: terraform destroy -var-file=terraform.tfvars -auto-approve
```

**Prod:**

```bash
cd envs/prod
terraform state rm aws_amplify_branch.production[0]   # if present
terraform destroy -var-file=terraform.tfvars
# or: terraform destroy -var-file=terraform.tfvars -auto-approve
```

## What Happens

1. ✅ Amplify branch is removed from Terraform state (but remains in AWS) when applicable
2. ✅ All other resources are destroyed
3. ✅ Amplify branch configuration in AWS remains intact (managed by Git)

## After Destruction

The Amplify branch will still exist in AWS but won’t be managed by Terraform. To manage it again with Terraform:

- **Dev:** `terraform import aws_amplify_branch.development[0] <app_id>/develop`
- **Prod:** `terraform import aws_amplify_branch.production[0] <app_id>/main`

Since the branch is Git-managed, you can also leave it unmanaged by Terraform.

