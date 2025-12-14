# Docker Installation Fix

## Root Cause
The user_data script failed during package installation due to a conflict between `curl-minimal` (pre-installed in Amazon Linux 2023) and `curl` package. Since the script uses `set -e`, it exited immediately, preventing Docker from being installed.

## Fix Applied
1. **Removed `curl` from installation** - Amazon Linux 2023 already has `curl-minimal` which provides the `curl` command
2. **Updated diagnostic script** - Fixed ECS security group detection to use Terraform output

## Next Steps

### Option 1: Recreate Instance (Recommended)
This ensures the fixed user_data script runs:
```bash
cd envs/dev
terraform taint module.opensearch_ec2[0].aws_instance.opensearch
terraform apply -var-file=terraform.tfvars
```

### Option 2: Manually Install Docker (Quick Fix)
If you want to fix the current instance without recreating:
```bash
INSTANCE_ID=$(terraform output -raw opensearch_ec2_instance_id)
aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo yum install -y docker", "sudo systemctl start docker", "sudo systemctl enable docker"]' \
  --output-s3-bucket-name "rentify-dev-logs" \
  --output-s3-key-prefix "ssm-commands"
```

Then manually run the OpenSearch container setup commands.

## Verification
After fixing, run:
```bash
./diagnose_opensearch_complete.sh
```

You should see:
- ✓ Docker installed
- ✓ OpenSearch container running
- ✓ Port 9200 listening
