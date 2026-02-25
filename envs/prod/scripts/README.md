# Utility Scripts

This directory contains **utility scripts for troubleshooting and diagnostics only**.

## ⚠️ Important

**For normal operations, you only need:**
- `terraform apply` - Deploy/update infrastructure
- `../destroy.sh` - Destroy infrastructure

**These utility scripts are for troubleshooting only!**

## Main Operations (Use These)

### `../destroy.sh` (in parent directory)
**Primary destroy script** - Use this for destroying all resources.

```bash
cd /Users/rohitsoni/Desktop/Rohit/Projects/shelf-shack-infra/envs/prod
./destroy.sh true YOUR_PASSWORD
```

## Utility Scripts (Troubleshooting Only)

### WebSocket Diagnostics

- **`check_websocket.sh`** - Quick check of WebSocket API configuration
- **`check_websocket_connection.sh`** - Test WebSocket connection end-to-end
- **`diagnose_and_fix_websocket.sh`** - Comprehensive WebSocket diagnostic and fix tool
- **`fix_websocket_backend.sh`** - Manually fix WebSocket Lambda backend URL (temporary fix)

### Lambda Deployment

- **`deploy_lambda_and_test.sh`** - Deploy WebSocket Lambda and test connection
- **`check_token_and_deploy.sh`** - Check token validation and deploy Lambda

### Legacy/Deprecated Scripts

These scripts are **deprecated** and will exit with an error message. Use `../destroy.sh` instead:

- **`destroy_all.sh`** - ❌ DEPRECATED (use `../destroy.sh`)
- **`force_destroy.sh`** - ❌ DEPRECATED (use `../destroy.sh`)
- **`delete_rds.sh`** - ❌ DEPRECATED (use `../destroy.sh`)
- **`cleanup_remaining.sh`** - ❌ DEPRECATED (use `../destroy.sh`)
- **`organize_scripts.sh`** - ❌ DEPRECATED (already organized)

## Usage

All scripts should be run from the `envs/prod/` directory:

```bash
cd /Users/rohitsoni/Desktop/Rohit/Projects/shelf-shack-infra/envs/prod

# Main operations (use these)
terraform apply -var-file=terraform.tfvars -var="db_master_password=..." -auto-approve
./destroy.sh true YOUR_PASSWORD

# Diagnostics (only if troubleshooting)
./scripts/check_websocket.sh
./scripts/diagnose_and_fix_websocket.sh
```

## When to Use Utility Scripts

Only use these scripts when:
- WebSocket connections are failing
- Lambda function needs manual debugging
- Troubleshooting specific issues

**For normal operations, use `terraform apply` and `./destroy.sh` only.**
