# Containerized OpenSearch Setup

## Overview

This setup uses OpenSearch as a containerized service running in ECS Fargate instead of AWS OpenSearch Service. This is a temporary workaround until moving to a paid AWS account, as AWS OpenSearch Service requires a paid account.

## Architecture

- **OpenSearch Image**: `opensearchproject/opensearch:2.11.0`
- **Deployment**: ECS Fargate service in private subnets
- **Security**: Disabled (plugins.security.disabled=true) for simplicity
- **Port**: 9200 (HTTP, not HTTPS)
- **Resources**: 512 CPU units, 1024 MB memory (free tier friendly)

## Configuration Changes

### Infrastructure (Terraform)

1. **AWS OpenSearch Service module is commented out** in `envs/dev/main.tf`
   - All related IAM policies and security groups are also commented out
   - Can be re-enabled when moving to paid account

2. **New containerized OpenSearch service** added:
   - Module: `modules/opensearch_container/`
   - Deployed in the same ECS cluster as the backend service
   - Uses private subnets with security group allowing access from backend service

### Backend Configuration

The backend application needs to be configured to connect to the containerized OpenSearch. Update your backend environment variables:

```bash
OPENSEARCH_HOST=<opensearch-service-endpoint>
OPENSEARCH_PORT=9200
OPENSEARCH_USE_SSL=false
OPENSEARCH_VERIFY_CERTS=false
```

#### Finding the OpenSearch Endpoint

Since both services are in the same VPC, you have a few options:

1. **Service Discovery (Recommended for production)**
   - Use AWS Cloud Map service discovery
   - DNS name: `<service-name>.<namespace>.local`
   - Requires additional Terraform configuration (see Future Improvements)

2. **Private IP (Temporary)**
   - Get the OpenSearch task's private IP from ECS console
   - Update backend environment variable
   - Note: IP changes when task restarts

3. **Service Name (if service discovery is configured)**
   - Use the ECS service name directly
   - Format: `rentify-dev-opensearch-service`

## Connecting to OpenSearch

### From Backend Application

The backend should connect using HTTP (not HTTPS) to port 9200. The OpenSearch client configuration in `app/search/opensearch_client.py` already supports this via environment variables.

### From Local Machine (for debugging)

To access OpenSearch from your local machine for debugging:

1. **Via ECS Exec** (recommended):
   ```bash
   aws ecs execute-command \
     --cluster <cluster-name> \
     --task <opensearch-task-id> \
     --container opensearch \
     --interactive \
     --command "/bin/bash"
   ```

2. **Via Bastion Host** (if enabled):
   - SSH to bastion
   - Use curl to test: `curl http://<opensearch-private-ip>:9200/_cluster/health`

## Security Considerations

⚠️ **Important**: Security is currently disabled (`plugins.security.disabled=true`) for simplicity. This means:
- No authentication required
- No encryption in transit
- Suitable for development/testing only

For production:
- Enable security plugin
- Configure TLS/SSL
- Set up authentication (basic auth or certificate-based)
- Update security groups to restrict access

## Monitoring

- **CloudWatch Logs**: `/ecs/<name>-opensearch/opensearch`
- **ECS Service**: Monitor task health in ECS console
- **Health Check**: OpenSearch has a built-in health check on port 9200

## Future Improvements

1. **Enable Service Discovery**
   - Add AWS Cloud Map namespace
   - Configure ECS service discovery for stable DNS names
   - Update backend to use DNS name instead of IP

2. **Enable Security**
   - Configure OpenSearch security plugin
   - Set up TLS certificates
   - Add authentication

3. **Add OpenSearch Dashboards**
   - Deploy `opensearchproject/opensearch-dashboards:2.11.0` as separate service
   - Configure to connect to OpenSearch container
   - Expose via ALB for browser access

4. **Migrate to AWS OpenSearch Service**
   - Uncomment AWS OpenSearch Service module
   - Remove containerized OpenSearch service
   - Update backend configuration for HTTPS and IAM auth

## Troubleshooting

### OpenSearch service not starting
- Check CloudWatch logs: `/ecs/<name>-opensearch/opensearch`
- Verify ECS task has sufficient resources (CPU/memory)
- Check security group rules allow traffic from backend

### Backend cannot connect to OpenSearch
- Verify security group allows traffic on port 9200
- Check OpenSearch task is running: `aws ecs list-tasks --cluster <cluster> --service-name <service>`
- Test connectivity from backend task using ECS Exec

### Performance issues
- Increase CPU/memory allocation in `opensearch_container` module
- Adjust Java heap size via `java_opts` variable
- Consider adding more instances (requires updating module)

## Rollback to AWS OpenSearch Service

If you need to switch back to AWS OpenSearch Service:

1. Uncomment the `module "opensearch"` block in `envs/dev/main.tf`
2. Comment out the `module "opensearch_container"` block
3. Update `module.ecs_service` to:
   - Set `opensearch_domain_arn = module.opensearch.domain_arn`
   - Set `enable_opensearch_access = true`
4. Remove dependency on `module.opensearch_container`
5. Run `terraform apply`

## Module Reference

### opensearch_container Module

**Location**: `modules/opensearch_container/`

**Variables**:
- `name`: Name prefix for resources
- `vpc_id`: VPC ID for deployment
- `subnet_ids`: Private subnet IDs
- `ecs_cluster_name`: ECS cluster name
- `allowed_security_group_ids`: Security groups allowed to access OpenSearch
- `container_image`: Docker image (default: `opensearchproject/opensearch:2.11.0`)
- `cpu`: Fargate CPU units (default: 512)
- `memory`: Fargate memory in MB (default: 1024)
- `java_opts`: Java options for JVM (default: `-Xms512m -Xmx512m`)

**Outputs**:
- `service_name`: ECS service name
- `security_group_id`: Security group ID
- `opensearch_port`: Port number (9200)







