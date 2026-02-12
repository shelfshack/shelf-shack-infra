# AWS Account Migration Guide

## Problem
You migrated from AWS account `506852294788` to `397562346696`, but Terraform state still references the old account. This causes Terraform to try destroying and recreating all resources.

## Solution Options

### Option A: Import Existing Resources (Recommended)
This preserves your existing infrastructure without downtime.

```bash
cd /path/to/shelf-shack-infra

# Run the import script
./scripts/import-existing-resources.sh dev

# Verify no destructive changes
cd envs/dev
terraform plan

# If plan looks good, apply
terraform apply
```

### Option B: Fresh Terraform State
If Option A doesn't work, reset Terraform state and let it adopt existing resources.

**⚠️ WARNING: Only do this if you understand the risks!**

```bash
cd envs/dev

# Backup current state
terraform state pull > terraform.tfstate.backup

# Remove all resources from state (doesn't delete from AWS)
terraform state list | xargs -n1 terraform state rm

# Reinitialize
terraform init -reconfigure

# Plan (should show it will import existing resources with create_if_not_exists=true)
terraform plan

# Apply carefully
terraform apply
```

### Option C: Manual Fix for Immediate Deployment

If you just need to deploy NOW and fix Terraform later:

1. **Skip Terraform in this deployment:**
   ```bash
   # In your deployment workflow, temporarily comment out the Terraform steps
   # Just build and push the Docker image, then manually update ECS
   ```

2. **Update ECS task manually:**
   ```bash
   # Force new deployment with latest image
   aws ecs update-service \
     --cluster shelfshack-dev-cluster \
     --service shelfshack-dev-service \
     --force-new-deployment \
     --region us-east-1
   ```

3. **Fix DATABASE_URL:**
   ```bash
   # Create RDS instance if it doesn't exist
   # Or update Secrets Manager to point to correct endpoint
   ```

## Current Issues to Fix

### 1. RDS Database
- **Status:** No RDS instance exists
- **Fix:** Create RDS instance or use existing one
- **Command:**
  ```bash
  aws rds describe-db-instances --region us-east-1
  ```

### 2. DATABASE_URL in Secrets Manager
- **Current:** Points to non-existent RDS endpoint
- **Fix:** Update with correct endpoint after RDS is created

### 3. Terraform State
- **Issue:** References old AWS account resources
- **Fix:** Import existing resources or start fresh

## Recommended Immediate Action

1. **Stop the failing deployment** (cancel the GitHub Actions workflow)
2. **Run the import script** to adopt existing resources
3. **Verify with `terraform plan`** that no resources will be destroyed
4. **Re-run deployment** once Terraform is stable

## Need Help?
If you're stuck, the safest approach is:
1. Keep existing infrastructure running AS-IS
2. Create a NEW Terraform workspace/state for the new account
3. Gradually migrate resources when ready
