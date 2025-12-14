# Bastion Host Disabled

## Changes Made

All bastion host resources have been commented out:

1. ✅ **Bastion Module** (`main.tf` lines 61-71)
   - Commented out the entire `module "bastion"` block

2. ✅ **RDS Security Group Rule** (`main.tf` lines 184-192)
   - Commented out `aws_security_group_rule.rds_from_bastion`

3. ✅ **OpenSearch Security Group Rule** (`main.tf` lines 238-247)
   - Commented out `aws_security_group_rule.opensearch_from_bastion`

4. ✅ **Bastion Output** (`outputs.tf` lines 31-34)
   - Commented out `output "bastion_instance_id"`

5. ✅ **Terraform Variables** (`terraform.tfvars` line 8-9)
   - Set `enable_bastion_host = false`
   - Commented out the old `true` value for reference

## Next Steps

Run `terraform plan` to verify no errors:

```bash
cd envs/dev
terraform plan -var-file=terraform.tfvars
```

If a bastion instance exists, it will be destroyed. If you want to keep it but just not manage it via Terraform, you can:

1. Remove it from Terraform state:
   ```bash
   terraform state rm module.bastion
   ```

2. Then run `terraform apply` to remove it from management

## Re-enabling in Future

To re-enable the bastion host in the future:

1. Uncomment all the commented sections
2. Set `enable_bastion_host = true` in `terraform.tfvars`
3. Run `terraform apply`

All code is preserved in comments for easy re-enablement.
