# Quick Start: WebSocket Lambda Setup (Option A)

This is a quick guide to set up Terraform-managed Lambda for WebSocket.

## ✅ Setup Complete!

The configuration is already set up for Option A (Terraform-managed Lambda). Here's what's configured:

### Local Development

**Current Setup:**
- ✅ Terraform module created (`modules/websocket_lambda/`)
- ✅ Variables defined in `envs/dev/variables.tf`
- ✅ Main configuration in `envs/dev/main.tf`
- ✅ Path configured in `envs/dev/terraform.tfvars` (using absolute path)

**To Deploy Locally:**

```bash
cd /Users/rohitsoni/Desktop/GitProjects/shelf-shack-infra/envs/dev

# Initialize Terraform (first time only)
terraform init

# Plan to see what will be created
terraform plan

# Apply to create resources
terraform apply
```

**What Terraform Will Create:**
1. DynamoDB table (`shelfshack-dev-websocket-connections`)
2. Lambda function (`shelfshack-dev-websocket-proxy`)
3. IAM roles and policies
4. API Gateway WebSocket API
5. API Gateway routes and integrations

### CI/CD Setup

**For GitHub Actions:**
- ✅ Workflow file created: `.github/workflows/terraform-deploy.yml`
- ⚠️ **Action Required:** Set these secrets in GitHub:
  - `BACKEND_REPO` - Repository name (e.g., `your-org/shelf-shack-backend`)
  - `BACKEND_REPO_TOKEN` - GitHub token with access to backend repo (if private)
  - `AWS_ACCESS_KEY_ID` - AWS credentials
  - `AWS_SECRET_ACCESS_KEY` - AWS credentials

**For GitLab CI:**
- ✅ CI file created: `.gitlab-ci.yml`
- ⚠️ **Action Required:** Set these variables in GitLab:
  - `BACKEND_REPO_URL` - Git URL to backend repo

**For Other CI/CD:**
- See `docs/CI_CD_SETUP.md` for detailed instructions

## Path Configuration

**Current Path in `terraform.tfvars`:**
```hcl
websocket_lambda_source_file = "/Users/rohitsoni/Desktop/GitProjects/shelf-shack-backend/lambda/websocket_proxy.py"
```

**Why Absolute Path?**
- Works reliably in all environments
- No dependency on directory structure
- Easy to override in CI/CD

**To Use Relative Path (if repos are siblings):**
```hcl
websocket_lambda_source_file = "../../shelf-shack-backend/lambda/websocket_proxy.py"
```

## Verification

After running `terraform apply`, verify:

1. **Check outputs:**
   ```bash
   terraform output websocket_api_endpoint
   terraform output websocket_lambda_function_arn
   ```

2. **Check AWS Console:**
   - Lambda function exists
   - DynamoDB table exists
   - API Gateway WebSocket API exists

3. **Test connection:**
   ```bash
   # Get WebSocket endpoint
   WS_URL=$(terraform output -raw websocket_api_endpoint)
   echo "Connect to: ${WS_URL}?type=chat&booking_id=1&token=YOUR_TOKEN"
   ```

## Next Steps

1. **Deploy infrastructure:**
   ```bash
   cd envs/dev
   terraform apply
   ```

2. **Get WebSocket endpoint:**
   ```bash
   terraform output websocket_api_endpoint
   ```

3. **Update frontend** to use the WebSocket endpoint

4. **Configure CI/CD** (if using):
   - Set required secrets/variables
   - Push to trigger deployment

## Troubleshooting

### "File not found" error

**Solution:** Update path in `terraform.tfvars`:
```hcl
websocket_lambda_source_file = "/absolute/path/to/backend/lambda/websocket_proxy.py"
```

### Lambda function already exists

**Solution:** Either:
1. Delete existing Lambda manually, or
2. Import it:
   ```bash
   terraform import module.websocket_lambda.aws_lambda_function.websocket_proxy your-lambda-name
   ```

### CI/CD can't find backend repo

**Solution:** 
- Check secrets/variables are set correctly
- Verify backend repo is accessible
- Use absolute path in CI environment variable

## Summary

✅ **Local:** Ready to use - just run `terraform apply`  
✅ **CI/CD:** Workflows created - set secrets/variables  
✅ **Path:** Using absolute path for reliability  

**Everything is configured for Option A (Terraform-managed Lambda)!**



