# Amplify Branch Import Guide

## Problem

When deploying infrastructure via CI/CD, you may encounter this error:

```
Error: creating Amplify Branch (d26vv4xxnh3x3s/develop): operation error Amplify: CreateBranch, 
BadRequestException: Failed to create branch. The branch develop already exists for the app d26vv4xxnh3x3s
```

This happens when:
- The Amplify branch exists in AWS (created manually or via Git)
- The branch is NOT in Terraform state
- Terraform tries to create it and fails because it already exists

## Solution

Import the existing branch into Terraform state **before** running `terraform apply`.

## Option 1: Add Import Step to GitHub Actions Workflow (Recommended)

Add this step to your `.github/workflows/deploy.yml` file in the **backend repository**, right before the `terraform apply` step:

```yaml
- name: Import Amplify branch if exists
  working-directory: envs/dev  # or envs/prod for production
  run: |
    terraform init -backend-config=backend.tf || true
    terraform import aws_amplify_branch.development[0] d26vv4xxnh3x3s/develop || true
  continue-on-error: true
```

**For Production:**
```yaml
- name: Import Amplify branch if exists
  working-directory: envs/prod
  run: |
    terraform init -backend-config=backend.tf || true
    terraform import aws_amplify_branch.production[0] d26vv4xxnh3x3s/main || true
  continue-on-error: true
```

The `|| true` ensures the workflow continues even if:
- The branch is already in state
- The branch doesn't exist (Terraform will create it)

## Option 2: Use the Import Script

If your workflow clones the infra repository, you can use the provided script:

```yaml
- name: Import Amplify branch if exists
  run: |
    cd shelf-shack-infra
    chmod +x scripts/import-amplify-branch.sh
    ./scripts/import-amplify-branch.sh dev
  continue-on-error: true
```

## Option 3: Manual Import (One-time Setup)

If you're setting up for the first time, you can import manually:

```bash
cd envs/dev
terraform init
terraform import aws_amplify_branch.development[0] d26vv4xxnh3x3s/develop
```

After importing, the branch will be managed by Terraform and the error won't occur again.

## Complete Workflow Example

Here's a complete example of how your terraform apply step should look:

```yaml
- name: Setup Terraform
  uses: hashicorp/setup-terraform@v2
  with:
    terraform_version: 1.5.0

- name: Checkout Infrastructure Repository
  uses: actions/checkout@v3
  with:
    repository: ${{ secrets.INFRA_REPOSITORY }}
    token: ${{ secrets.INFRA_REPO_TOKEN }}
    path: shelf-shack-infra

- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v2
  with:
    role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
    aws-region: ${{ secrets.AWS_REGION }}

- name: Import Amplify branch if exists
  working-directory: shelf-shack-infra/envs/dev
  run: |
    terraform init -backend-config=backend.tf || true
    terraform import aws_amplify_branch.development[0] d26vv4xxnh3x3s/develop || true
  continue-on-error: true

- name: Terraform Apply
  working-directory: shelf-shack-infra/envs/dev
  run: |
    terraform init -backend-config=backend.tf
    terraform apply -auto-approve -var-file=terraform.tfvars \
      -var="container_image_tag=${{ github.sha }}"
```

## Verification

After adding the import step, verify it works:

1. Check the workflow logs - you should see either:
   - "Successfully imported Amplify branch" (if it was imported)
   - "Branch is already in Terraform state" (if already imported)
   - No error (if branch doesn't exist and will be created)

2. After the first successful import, subsequent runs will skip the import (branch is already in state)

## Troubleshooting

### Error: "Resource already managed by Terraform"
This means the branch is already in state. The import step will skip it automatically. This is safe to ignore.

### Error: "Branch does not exist"
This means the branch doesn't exist in AWS. Terraform will create it on apply. This is expected behavior.

### Import fails but apply succeeds
This can happen if there's a timing issue. The `|| true` ensures the workflow continues. If the branch is in AWS, Terraform will update it instead of creating it (due to the lifecycle block).

## Notes

- The import only needs to happen **once** per branch. After that, Terraform manages it.
- The `lifecycle { prevent_destroy = true }` block ensures Terraform won't accidentally delete Git-managed branches.
- The `ignore_changes` block ensures Terraform only manages environment variables, not branch settings managed by Git.

