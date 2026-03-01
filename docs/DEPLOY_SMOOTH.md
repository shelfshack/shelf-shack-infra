# Smooth deployment: why it failed and how to run it

## Why the apply failed

The error was:

```text
Error: deleting RDS Subnet Group (shelfshack-prod-db-subnets): ... Cannot delete the subnet group 'shelfshack-prod-db-subnets' because at least one database instance: shelfshack-prod-postgres is still using it.
```

Cause:

1. The **RDS module** uses a “create if not exists” pattern. When it sees the subnet group already in AWS, it sets **count = 0** for `aws_db_subnet_group.this`.
2. Terraform then **plans to destroy** that subnet group (no longer in config).
3. The **DB instance** was just created (or already exists) and **uses that subnet group**.
4. AWS does not allow deleting a subnet group that is in use, so the destroy step fails.

So the failure was from the RDS “use existing” logic planning to destroy the subnet group while the DB instance still depended on it.

## What was changed

**RDS module (`modules/rds_postgres/main.tf`):**

- The “use existing” path was removed for the **subnet group**, **security group**, and **DB instance**.
- The module **always creates** these resources (same idea as the networking module):
  - `should_create_subnet_group = true`
  - `should_create_security_group = true`
  - `should_create_db_instance = true`
- So a normal **apply no longer plans to destroy** the RDS subnet group or instance; it only creates/updates.

With this and the earlier networking fix, **full `terraform apply`** should no longer plan to destroy VPC/IGW/subnets or RDS subnet group/instance.

## Option A: Clean destroy, then apply from scratch

Use this when you want to tear everything down and redeploy cleanly.

1. **Destroy (recommended: use the script so destroy doesn’t get stuck on ECS):**

   ```bash
   ./scripts/destroy.sh prod --auto-approve   # or dev
   ```

   The script first scales the ECS service to 0 and waits for tasks to drain, then runs `terraform destroy`.    If destroy **still gets stuck** on ECS, use the **force-destroy** script (deletes ECS in AWS first, then removes from state and destroys the rest):

   ```bash
   ./scripts/force-destroy.sh prod --auto-approve   # or dev
   ```

   Or manually: `./scripts/pre-destroy-scale-ecs-zero.sh prod`, then `terraform destroy` from `envs/prod`.

   Terraform will destroy in dependency order (e.g. DB instance, then subnet group). This can take several minutes (RDS, ECS, etc.).

2. **Apply from scratch:**

   ```bash
   terraform apply -var-file=terraform.tfvars -auto-approve
   ```

   Ensure **DB_MASTER_PASSWORD** is set (e.g. `export TF_VAR_DB_MASTER_PASSWORD=yourpassword` or use `db_master_password_secret_arn` in tfvars).

## Option B: Fix current state and continue (no full destroy)

Use this when you want to keep the current env and only fix the failed apply.

1. **Re-run apply** (with the RDS fix in place):

   ```bash
   cd envs/prod
   terraform apply -var-file=terraform.tfvars -auto-approve
   ```

   With the updated RDS module, Terraform should **not** plan to destroy the subnet group, so the apply can complete. Resolve any other plan changes (e.g. DynamoDB/Lambda) as needed.

## Prod `terraform.tfvars` checklist

- **db_master_password**: Set via `TF_VAR_DB_MASTER_PASSWORD` or `db_master_password_secret_arn` (prod tfvars has secrets ARNs; password can also come from env).
- **db_skip_final_snapshot**: `true` in prod so destroy does not require a final snapshot.
- **db_deletion_protection**: `false` in prod so destroy can delete the DB.
- **http_api_cors_origins**: Set to your real origins (shelfshack.com, Amplify URLs, localhost) for CORS.
- **app_secrets**: All point to the correct prod secret ARN (`backend_secrets-XwsTaO`).

No tfvars changes were required for the RDS fix; the module change alone fixes the subnet group destroy error.

## Summary

| Issue | Fix |
|-------|-----|
| Apply tried to destroy RDS subnet group while DB instance used it | RDS module now always creates subnet group and DB instance (no conditional count=0). |
| Apply previously tried to destroy VPC/IGW/subnets | Networking module was already updated to always create. |
| Clean slate | Run `terraform destroy` then `terraform apply` (Option A). |
| Continue without full destroy | Run `terraform apply` again with the fixed modules (Option B). |
