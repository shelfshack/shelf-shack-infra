# Terraform Idempotency Improvements

## Problem Statement

When running `terraform apply` on an existing infrastructure, Terraform was attempting to destroy and recreate resources unnecessarily, causing failures and downtime. The goal was to make Terraform idempotent - when applying again, it should:

1. **Check if resources exist** - Don't recreate them if they already exist
2. **Only update what changed** - Redeploy ECS service, update API Gateway integrations with new IPs
3. **Update Amplify env vars** - Only when API Gateway endpoints actually change
4. **Prevent accidental destruction** - Critical resources should not be destroyed on reapply

## Solution: Comprehensive Lifecycle Management

### 1. Prevent Resource Destruction

Added `prevent_destroy = true` to critical resources:

- **API Gateway (HTTP & WebSocket)**: Prevents accidental deletion
- **IAM Deploy Role**: Prevents deletion of deployment role
- **Route53 Records**: Prevents DNS record deletion

### 2. Optimize External Data Source

The ECS task public IP data source now:
- Only refreshes when `task_definition_arn` changes (new deployment)
- Uses task definition ARN as primary trigger
- Prevents unnecessary IP lookups on every apply

### 3. API Gateway Integration Updates

API Gateway integrations now:
- Update **in-place** when backend URL changes (new ECS task IP)
- Use `create_before_destroy = false` to ensure updates, not recreations
- Allow `integration_uri` to update without resource recreation

### 4. Amplify Environment Variables

Amplify env vars now only update when:
- API Gateway IDs actually change (new API created)
- Custom environment variables change
- NOT on every apply (prevents unnecessary API calls)

### 5. Resource Lifecycle Rules

All major resources now have lifecycle rules:

```hcl
lifecycle {
  prevent_destroy = true  # For critical resources
  create_before_destroy = true  # For resources that can be recreated
  ignore_changes = [tags["ManagedBy"]]  # Allow tag updates
}
```

## How It Works Now

### First Apply (Clean Slate)
1. Creates all resources (VPC, RDS, ECS, API Gateway, etc.)
2. Deploys ECS service
3. Fetches ECS task public IP
4. Configures API Gateway integrations
5. Updates Amplify environment variables

### Subsequent Applies (Idempotent)
1. **Checks existing resources** - No recreation if they exist
2. **Redeploys ECS service** - Only if `force_new_deployment = true` or task definition changed
3. **Fetches new IP** - Only if task definition changed (new deployment)
4. **Updates API Gateway** - Integration URI updates in-place with new IP
5. **Updates Amplify** - Only if API Gateway IDs changed or custom vars changed
6. **No destruction** - Critical resources protected from accidental deletion

## Key Improvements

### External Data Source Optimization
```hcl
query = {
  task_def_arn = module.ecs_service.task_definition_arn  # Primary trigger
  service_name = module.ecs_service.service_name
  cluster_name = module.ecs_service.cluster_name
}
```
- Only refreshes when task definition changes
- Prevents unnecessary IP lookups

### API Gateway Lifecycle
```hcl
lifecycle {
  prevent_destroy = true
  ignore_changes = [description, tags["ManagedBy"]]
}
```
- Prevents accidental deletion
- Allows tag updates without recreation

### Integration Updates
```hcl
lifecycle {
  create_before_destroy = false
  # Allows integration_uri to update in-place
}
```
- Updates integration URI when IP changes
- No resource recreation

### Amplify Trigger Optimization
```hcl
triggers = {
  http_api_id = aws_apigatewayv2_api.backend.id
  websocket_api_id = aws_apigatewayv2_api.websocket.id
  custom_env_vars_hash = sha256(jsonencode(var.amplify_branch_environment_variables))
}
```
- Only updates when API IDs change
- Prevents unnecessary Amplify API calls

## Best Practices

1. **Use `terraform plan` first** - Always review changes before applying
2. **Set `force_new_deployment = false`** - In production to prevent unnecessary redeployments
3. **Monitor external data source** - Check if IP lookup is taking too long
4. **Review lifecycle rules** - Ensure critical resources have `prevent_destroy = true`

## Troubleshooting

### Resources Still Being Recreated
- Check if `prevent_destroy = true` is set
- Verify `ignore_changes` includes computed values
- Review module lifecycle rules

### API Gateway Integration Not Updating
- Check if `integration_uri` is in `ignore_changes` (should NOT be)
- Verify `create_before_destroy = false` is set
- Ensure backend URL is computed correctly

### Amplify Updating Too Frequently
- Check trigger conditions
- Verify API Gateway IDs are stable
- Review custom environment variables

## Migration Notes

When upgrading existing infrastructure:
1. Run `terraform plan` to see what would change
2. Review lifecycle rules for each resource
3. Apply changes incrementally if needed
4. Monitor for any unexpected recreations
