# WebSocket Lambda Deployment Options

This document explains how Lambda function deployment works and your options.

## How Terraform Deploys Lambda Functions

When you run `terraform apply`, Terraform:

1. **Reads the source file** from your backend repo (via `archive_file` data source)
2. **Packages it** into a ZIP file (creates `lambda_function.zip` in the module directory)
3. **Uploads to AWS** Lambda service automatically
4. **Creates/updates** the Lambda function with the new code

**This happens automatically** - you don't need to manually upload anything.

## Directory Structure Requirements

For Terraform to find the Lambda source file, the backend repo must be accessible:

```
GitProjects/
├── shelf-shack-backend/          # Backend repo
│   └── lambda/
│       └── websocket_proxy.py    # Lambda source file
└── shelf-shack-infra/            # Infra repo
    └── envs/
        └── dev/                  # Terraform runs from here
            └── main.tf
```

**From `envs/dev/` directory:**
- `../../` → goes to `shelf-shack-infra/` (infra repo root)
- `../shelf-shack-backend/` → goes to sibling backend repo
- Full path: `../../shelf-shack-backend/lambda/websocket_proxy.py`

## Option 1: Terraform-Managed Lambda (Recommended)

**Pros:**
- ✅ Automatic deployments - just run `terraform apply`
- ✅ Version control - code changes tracked in git
- ✅ Infrastructure as Code - everything in one place
- ✅ Easy updates - change code, run terraform, done

**Cons:**
- ❌ Requires backend repo to be accessible from infra repo
- ❌ Slightly slower (packages on each apply if code changed)

**Setup:**

1. Ensure backend repo is accessible (sibling directory or adjust path)
2. Set variable in `terraform.tfvars`:
   ```hcl
   websocket_lambda_source_file = "../../shelf-shack-backend/lambda/websocket_proxy.py"
   ```
3. Run `terraform apply` - Terraform handles everything

**How to verify it works:**
```bash
cd envs/dev
terraform plan  # Should show "aws_lambda_function.websocket_proxy will be created"
```

## Option 2: Use Existing Manually-Uploaded Lambda

If you've already uploaded the Lambda function manually via AWS Console or CLI:

**Pros:**
- ✅ No repo access needed
- ✅ Can use existing Lambda

**Cons:**
- ❌ Manual updates required (upload code separately)
- ❌ Not Infrastructure as Code
- ❌ Terraform won't manage the function code

**Setup:**

1. **Modify `envs/dev/main.tf`** - Comment out the module and use data source:

```hcl
# Comment out or remove this:
# module "websocket_lambda" {
#   source = "../../modules/websocket_lambda"
#   ...
# }

# Add this instead:
data "aws_lambda_function" "existing_websocket" {
  function_name = "your-lambda-function-name"  # Name of your existing Lambda
}

# Update the integration to reference existing Lambda:
resource "aws_apigatewayv2_integration" "websocket" {
  api_id           = aws_apigatewayv2_api.websocket.id
  integration_type = "AWS_PROXY"
  integration_uri  = data.aws_lambda_function.existing_websocket.invoke_arn
}

# Still need DynamoDB table (or reference existing one):
resource "aws_dynamodb_table" "websocket_connections" {
  name           = "${local.name}-websocket-connections"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "booking_id"
  range_key      = "connection_id"
  # ... rest of table config
}
```

2. **Update Lambda manually** when code changes:
   ```bash
   cd /path/to/shelf-shack-backend
   zip lambda_function.zip lambda/websocket_proxy.py
   aws lambda update-function-code \
     --function-name your-lambda-function-name \
     --zip-file fileb://lambda_function.zip
   ```

## Option 3: Hybrid Approach (Recommended for Flexibility)

Use Terraform to manage infrastructure (DynamoDB, API Gateway, IAM) but reference existing Lambda:

```hcl
# Terraform creates everything EXCEPT Lambda function
module "websocket_lambda" {
  source = "../../modules/websocket_lambda"
  # ... but skip Lambda creation
  create_lambda = false  # Add this to module if supported
}

# Reference your existing Lambda
data "aws_lambda_function" "existing" {
  function_name = "your-existing-lambda"
}

# Use existing Lambda in integration
resource "aws_apigatewayv2_integration" "websocket" {
  integration_uri = data.aws_lambda_function.existing.invoke_arn
  # ...
}
```

## Which Option Should You Use?

**Use Option 1 (Terraform-managed) if:**
- ✅ You want Infrastructure as Code
- ✅ You want automatic deployments
- ✅ Backend repo is accessible from infra repo
- ✅ You're okay with Terraform managing the Lambda

**Use Option 2 (Existing Lambda) if:**
- ✅ Lambda is already uploaded and working
- ✅ You prefer manual code updates
- ✅ Backend repo is not accessible
- ✅ You have CI/CD pipeline that handles Lambda separately

**Recommendation:** Use Option 1 for new deployments. It's cleaner and more maintainable.

## Troubleshooting

### "File not found" error

**Problem:** Terraform can't find the Lambda source file.

**Solutions:**
1. **Use absolute path:**
   ```hcl
   websocket_lambda_source_file = "/Users/rohitsoni/Desktop/GitProjects/shelf-shack-backend/lambda/websocket_proxy.py"
   ```

2. **Verify path exists:**
   ```bash
   cd envs/dev
   ls -la ../../shelf-shack-backend/lambda/websocket_proxy.py
   ```

3. **Check directory structure:**
   ```bash
   # From infra repo root
   ls -la ../shelf-shack-backend/lambda/websocket_proxy.py
   ```

### Lambda function already exists

**Problem:** `Error: creating Lambda Function: ResourceConflictException`

**Solution:** Either:
1. Delete existing Lambda manually, or
2. Import it into Terraform:
   ```bash
   terraform import module.websocket_lambda.aws_lambda_function.websocket_proxy your-lambda-function-name
   ```

### Different directory structure

If your repos are in different locations, use absolute path:

```hcl
variable "websocket_lambda_source_file" {
  default = "/absolute/path/to/shelf-shack-backend/lambda/websocket_proxy.py"
}
```

## Summary

- **Terraform DOES upload and deploy Lambda automatically** when using the module
- **Backend repo access is only needed** if you want Terraform to manage the Lambda code
- **If Lambda is already uploaded**, you can reference it instead of creating new one
- **Recommended:** Let Terraform manage everything for easier deployments



