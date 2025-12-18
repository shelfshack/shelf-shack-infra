# Apply Terraform Changes

## Current Status
You've run `terraform plan` and Terraform is ready to apply changes.

## Next Step: Apply

Run this command to recreate the instance with the fixed user_data:

```bash
terraform apply -var-file=terraform.tfvars
```

When prompted, type `yes` to confirm.

## What Will Happen

1. **Destroy** the old EC2 instance (with broken user_data)
2. **Create** a new EC2 instance with fixed user_data script
3. The new user_data will:
   - Install Docker correctly (no curl conflict)
   - Start OpenSearch container with password (even when security disabled)
   - Configure network binding to 0.0.0.0
   - Include all error handling improvements

## After Apply

### 1. Wait 5-8 minutes
- Instance creation: ~2 minutes
- User data execution: ~2-3 minutes
- OpenSearch initialization: ~1-2 minutes

### 2. Verify
```bash
./diagnose_opensearch_complete.sh
```

Should show:
- ✅ Container running
- ✅ Port 9200 listening
- ✅ Health check passing

### 3. Restart ECS Service
```bash
aws ecs update-service \
  --cluster shelfshack-dev-cluster \
  --service shelfshack-dev-service \
  --force-new-deployment
```

### 4. Monitor Logs
```bash
aws logs tail /ecs/shelfshack-dev --follow
```

You should see successful OpenSearch connections!

## Expected Timeline

- Terraform apply: ~3-5 minutes
- Instance initialization: ~5-8 minutes
- **Total: ~8-13 minutes** before OpenSearch is fully ready
