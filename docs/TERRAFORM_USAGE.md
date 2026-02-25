# Terraform Usage Guide - Simple Commands

This guide shows you how to use Terraform with a single command for apply, reapply, and destroy operations.

## 🎯 Single Command Operations

### Apply (First Time or Reapply)

```bash
cd envs/prod
terraform apply -var-file=terraform.tfvars -var="db_master_password=YOUR_PASSWORD" -auto-approve
```

**What it does:**
- Creates all infrastructure if it doesn't exist
- Updates existing resources if configuration changed
- Redeploys ECS service if needed
- Updates API Gateway integrations with new IPs
- Updates Amplify environment variables
- **No manual steps required** - fully automated and idempotent

### Destroy (Complete Cleanup)

```bash
cd envs/prod
terraform destroy -var-file=terraform.tfvars -var="allow_destruction=true" -var="db_master_password=YOUR_PASSWORD" -auto-approve
```

**What it does automatically:**
- ✅ Disables RDS deletion protection
- ✅ Empties S3 bucket
- ✅ Removes destroy protection checks
- ✅ Destroys all resources in correct order
- **No scripts needed** - everything is handled by Terraform

## 🔒 Protection Mechanism

By default, resources are **protected** from accidental destruction:
- `allow_destruction = false` (default) - Prevents `terraform destroy`
- `allow_destruction = true` - Allows `terraform destroy`

## 📝 Examples

### Production Environment

**Apply/Reapply:**
```bash
cd envs/prod
terraform apply -var-file=terraform.tfvars -var="db_master_password=MySecurePassword123" -auto-approve
```

**Destroy:**
```bash
cd envs/prod
terraform destroy -var-file=terraform.tfvars -var="allow_destruction=true" -var="db_master_password=MySecurePassword123" -auto-approve
```

### Development Environment

**Apply/Reapply:**
```bash
cd envs/dev
terraform apply -var-file=terraform.tfvars -var="db_master_password=MySecurePassword123" -auto-approve
```

**Destroy:**
```bash
cd envs/dev
terraform destroy -var-file=terraform.tfvars -var="allow_destruction=true" -var="db_master_password=MySecurePassword123" -auto-approve
```

## 🛡️ Safety Features

1. **Default Protection**: Resources are protected by default (`allow_destruction=false`)
2. **Explicit Permission**: Must set `allow_destruction=true` to destroy
3. **Automatic Cleanup**: S3 buckets are automatically emptied before deletion
4. **RDS Protection**: Deletion protection is automatically disabled when `allow_destruction=true`
5. **Idempotent Apply**: Reapplying is safe and only updates what changed

## ⚠️ Important Notes

- **Password Required**: Always provide `db_master_password` in commands
- **Auto-approve**: Use `-auto-approve` to skip confirmation prompts
- **No Scripts Needed**: Everything is handled by Terraform configuration
- **Safe Reapply**: Running `terraform apply` multiple times is safe and idempotent

## 🎓 For Beginners

Even if you're new to Terraform, you can use these commands:

1. **To deploy/update infrastructure:**
   ```bash
   terraform apply -var-file=terraform.tfvars -var="db_master_password=YOUR_PASSWORD" -auto-approve
   ```

2. **To destroy everything:**
   ```bash
   terraform destroy -var-file=terraform.tfvars -var="allow_destruction=true" -var="db_master_password=YOUR_PASSWORD" -auto-approve
   ```

That's it! No complex scripts, no manual steps, no confusion.
