# CI/CD Setup for WebSocket Lambda Deployment

This guide explains how to configure CI/CD pipelines to deploy the WebSocket Lambda function managed by Terraform.

## Overview

When Terraform deploys the Lambda function, it needs access to the Lambda source file from the backend repo. In CI/CD environments, you need to ensure both repos are checked out.

## Local Development

**No special setup needed** - as long as both repos are in the same parent directory:

```
GitProjects/
├── shelf-shack-backend/
└── shelf-shack-infra/
```

The default path `../../shelf-shack-backend/lambda/websocket_proxy.py` works from `envs/dev/`.

## CI/CD Setup

### Option 1: Checkout Both Repos (Recommended)

Checkout both the infra repo and backend repo in your CI/CD pipeline.

#### GitHub Actions

**File**: `.github/workflows/terraform-deploy.yml`

```yaml
steps:
  - name: Checkout Infrastructure Repo
    uses: actions/checkout@v4
    with:
      path: infra
  
  - name: Checkout Backend Repo
    uses: actions/checkout@v4
    with:
      repository: your-org/shelf-shack-backend
      path: backend
      token: ${{ secrets.BACKEND_REPO_TOKEN }}  # If private repo
  
  - name: Terraform Apply
    working-directory: infra/envs/dev
    env:
      TF_VAR_websocket_lambda_source_file: "${{ github.workspace }}/backend/lambda/websocket_proxy.py"
    run: terraform apply -auto-approve
```

**Required Secrets:**
- `BACKEND_REPO_TOKEN` - GitHub token with access to backend repo (if private)

#### GitLab CI

**File**: `.gitlab-ci.yml`

```yaml
variables:
  BACKEND_REPO_PATH: ${CI_PROJECT_DIR}/../shelf-shack-backend

terraform:apply:
  before_script:
    - |
      # Clone backend repo
      if [ ! -d "${BACKEND_REPO_PATH}" ]; then
        git clone ${BACKEND_REPO_URL} ${BACKEND_REPO_PATH}
      fi
  script:
    - |
      cd envs/dev
      terraform apply \
        -var="websocket_lambda_source_file=${BACKEND_REPO_PATH}/lambda/websocket_proxy.py" \
        -auto-approve
```

**Required Variables:**
- `BACKEND_REPO_URL` - Git URL to backend repo

#### Jenkins

**Jenkinsfile**:

```groovy
pipeline {
    agent any
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm  // Infra repo
                dir('backend') {
                    git url: 'https://github.com/your-org/shelf-shack-backend.git'
                }
            }
        }
        
        stage('Terraform Apply') {
            steps {
                dir('envs/dev') {
                    sh '''
                        terraform apply \
                          -var="websocket_lambda_source_file=${WORKSPACE}/backend/lambda/websocket_proxy.py" \
                          -auto-approve
                    '''
                }
            }
        }
    }
}
```

### Option 2: Use Git Submodules

If both repos are in the same organization, you can use Git submodules:

```bash
# In infra repo
git submodule add https://github.com/your-org/shelf-shack-backend.git backend
```

Then in `terraform.tfvars`:
```hcl
websocket_lambda_source_file = "../backend/lambda/websocket_proxy.py"
```

**Note:** Remember to initialize submodules in CI:
```yaml
- run: git submodule update --init --recursive
```

### Option 3: Package Lambda Separately

If you can't checkout the backend repo in CI, package the Lambda ZIP separately:

1. **In backend repo CI**, create Lambda ZIP:
   ```bash
   zip lambda_function.zip lambda/websocket_proxy.py
   # Upload to S3 or artifact storage
   ```

2. **In infra repo CI**, download and use:
   ```hcl
   # In terraform.tfvars or via variable
   websocket_lambda_source_file = "/tmp/lambda_function.zip"
   ```

3. **Update Terraform module** to handle ZIP files:
   ```hcl
   # In modules/websocket_lambda/main.tf
   data "archive_file" "lambda_zip" {
     type        = var.lambda_source_is_zip ? "zip" : "zip"
     source_file = var.lambda_source_file
     # ... or use existing ZIP if provided
   }
   ```

## Environment Variables

You can override the Lambda source file path via environment variable:

```bash
export TF_VAR_websocket_lambda_source_file="/absolute/path/to/lambda/websocket_proxy.py"
terraform apply
```

This is useful in CI/CD where paths might differ.

## Verification

After setting up CI/CD, verify it works:

1. **Check Terraform plan output** - should show Lambda function creation
2. **Check Lambda function exists** in AWS after deployment
3. **Check Lambda code** - verify it matches your source file

## Troubleshooting

### "File not found" in CI/CD

**Problem:** Terraform can't find Lambda source file in CI.

**Solutions:**
1. **Use absolute path** in CI:
   ```yaml
   env:
     TF_VAR_websocket_lambda_source_file: "${{ github.workspace }}/backend/lambda/websocket_proxy.py"
   ```

2. **Verify checkout** - ensure backend repo is checked out:
   ```bash
   ls -la backend/lambda/websocket_proxy.py
   ```

3. **Use debug output**:
   ```yaml
   - run: |
       echo "Workspace: ${{ github.workspace }}"
       ls -la backend/lambda/ || echo "Backend not found"
   ```

### Backend repo is private

**GitHub Actions:**
```yaml
- uses: actions/checkout@v4
  with:
    repository: your-org/shelf-shack-backend
    token: ${{ secrets.BACKEND_REPO_TOKEN }}
```

**GitLab CI:**
```yaml
- git clone https://oauth2:${CI_JOB_TOKEN}@gitlab.com/your-org/shelf-shack-backend.git
```

### Different repo structures

If repos are in different locations, use absolute paths:

```hcl
# In terraform.tfvars or CI environment variable
websocket_lambda_source_file = "/build/backend/lambda/websocket_proxy.py"
```

## Best Practices

1. **Use environment variables** for paths in CI/CD (more flexible)
2. **Cache backend repo** if possible (faster builds)
3. **Verify paths** in CI logs before Terraform runs
4. **Use separate workflows** for infra and backend if needed
5. **Tag Lambda versions** for easier rollback

## Example: Complete GitHub Actions Workflow

See `.github/workflows/terraform-deploy.yml` for a complete example.

## Summary

- **Local**: No setup needed if repos are siblings
- **CI/CD**: Checkout both repos, use absolute paths
- **Alternative**: Use submodules or package Lambda separately
- **Override**: Use `TF_VAR_websocket_lambda_source_file` environment variable




