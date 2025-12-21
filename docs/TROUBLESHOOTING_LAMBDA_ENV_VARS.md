# Troubleshooting: Lambda Environment Variables Not Showing

If you don't see `CONNECTIONS_TABLE` or other environment variables in your AWS Lambda function, here's how to fix it.

## Quick Check

**Lambda Function Name:** `shelfshack-dev-websocket-proxy`

**Expected Environment Variables:**
- `CONNECTIONS_TABLE` = `shelfshack-dev-websocket-connections`
- `BACKEND_URL` = Your backend URL
- `API_GATEWAY_ENDPOINT` = API Gateway endpoint URL

## Possible Issues

### Issue 1: Lambda Created Manually (Not by Terraform)

**Symptom:** Lambda exists in AWS but environment variables are missing.

**Solution:** 
1. **Option A - Let Terraform manage it:**
   ```bash
   # Delete the manually created Lambda in AWS Console
   # Then run:
   cd envs/dev
   terraform apply
   ```

2. **Option B - Import existing Lambda:**
   ```bash
   cd envs/dev
   terraform import module.websocket_lambda.aws_lambda_function.websocket_proxy shelfshack-dev-websocket-proxy
   terraform apply  # This will update it with environment variables
   ```

### Issue 2: Terraform Not Applied Yet

**Symptom:** Terraform code exists but hasn't been applied.

**Solution:**
```bash
cd envs/dev
terraform init
terraform plan  # Review changes
terraform apply  # Apply to create/update Lambda with env vars
```

### Issue 3: Looking at Wrong Lambda Function

**Symptom:** Environment variables exist but in a different Lambda.

**Solution:**
- Check Lambda function name: `shelfshack-dev-websocket-proxy`
- Verify in AWS Console: Lambda → Functions → `shelfshack-dev-websocket-proxy`
- Or check via CLI:
  ```bash
  aws lambda get-function-configuration \
    --function-name shelfshack-dev-websocket-proxy \
    --query 'Environment.Variables'
  ```

### Issue 4: Terraform State Out of Sync

**Symptom:** Terraform thinks it's configured but AWS doesn't have the vars.

**Solution:**
```bash
cd envs/dev
terraform refresh  # Sync state with AWS
terraform plan     # See what needs updating
terraform apply    # Apply changes
```

## Verify Environment Variables

### Via AWS Console
1. Go to AWS Lambda Console
2. Find function: `shelfshack-dev-websocket-proxy`
3. Go to **Configuration** → **Environment variables**
4. Should see:
   - `CONNECTIONS_TABLE`
   - `BACKEND_URL`
   - `API_GATEWAY_ENDPOINT`

### Via AWS CLI
```bash
aws lambda get-function-configuration \
  --function-name shelfshack-dev-websocket-proxy \
  --query 'Environment.Variables' \
  --output json
```

### Via Terraform
```bash
cd envs/dev
terraform show | grep -A 10 "environment"
```

## Manual Fix (Temporary)

If you need to set environment variables manually while fixing Terraform:

```bash
aws lambda update-function-configuration \
  --function-name shelfshack-dev-websocket-proxy \
  --environment "Variables={CONNECTIONS_TABLE=shelfshack-dev-websocket-connections,BACKEND_URL=https://your-backend-url.com,API_GATEWAY_ENDPOINT=https://your-api-gateway.execute-api.us-east-1.amazonaws.com/development}"
```

**Note:** This is temporary - Terraform will overwrite on next apply. Better to fix Terraform.

## Check Terraform Configuration

Verify the module is correctly configured:

```bash
cd envs/dev
terraform plan | grep -A 5 "environment"
```

Should show:
```
+ environment {
    + variables = {
        + API_GATEWAY_ENDPOINT = "..."
        + BACKEND_URL          = "..."
        + CONNECTIONS_TABLE    = "shelfshack-dev-websocket-connections"
      }
    }
```

## Force Update

If environment variables should be there but aren't:

```bash
cd envs/dev
# Force Terraform to update Lambda
terraform apply -replace=module.websocket_lambda.aws_lambda_function.websocket_proxy
```

Or update just the environment:

```bash
terraform apply -target=module.websocket_lambda.aws_lambda_function.websocket_proxy
```

## Common Mistakes

1. **Wrong Lambda function** - Make sure you're looking at `shelfshack-dev-websocket-proxy`
2. **Terraform not applied** - Code exists but `terraform apply` wasn't run
3. **Manual Lambda** - Lambda created manually, not by Terraform
4. **State mismatch** - Terraform state doesn't match AWS reality

## Next Steps

1. **Verify Lambda exists:**
   ```bash
   aws lambda get-function --function-name shelfshack-dev-websocket-proxy
   ```

2. **Check if managed by Terraform:**
   ```bash
   cd envs/dev
   terraform state list | grep lambda
   ```

3. **Apply Terraform:**
   ```bash
   terraform apply
   ```

4. **Verify environment variables:**
   ```bash
   aws lambda get-function-configuration \
     --function-name shelfshack-dev-websocket-proxy \
     --query 'Environment.Variables.CONNECTIONS_TABLE'
   ```

## Summary

- **If Lambda was created manually:** Delete it and let Terraform create it, or import it
- **If Terraform not applied:** Run `terraform apply`
- **If wrong Lambda:** Check function name `shelfshack-dev-websocket-proxy`
- **If state mismatch:** Run `terraform refresh` then `terraform apply`

The environment variables should be automatically set by Terraform when you run `terraform apply`.



