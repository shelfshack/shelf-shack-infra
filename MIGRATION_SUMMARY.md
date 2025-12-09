# OpenSearch Migration Summary: AWS Service → Containerized ECS Service

## What Was Changed

### ✅ Completed Tasks

1. **Created new OpenSearch Container Module** (`modules/opensearch_container/`)
   - Uses `opensearchproject/opensearch:2.11.0` image
   - Configured for ECS Fargate deployment
   - Security disabled for simplicity
   - Free tier friendly (512 CPU, 1024 MB memory)

2. **Commented out AWS OpenSearch Service**
   - All AWS OpenSearch Service resources in `envs/dev/main.tf` are commented out
   - IAM policies and security group rules are preserved but commented
   - Easy to re-enable when moving to paid account

3. **Added Containerized OpenSearch Service**
   - Deployed in same ECS cluster as backend
   - Uses private subnets
   - Security group allows access from backend service

4. **Updated Infrastructure**
   - ECS service module updated to handle null OpenSearch domain ARN
   - Outputs updated to show containerized OpenSearch service info
   - Backend service no longer requires OpenSearch IAM policies

### 📝 Files Modified

#### New Files
- `modules/opensearch_container/main.tf` - OpenSearch container service definition
- `modules/opensearch_container/variables.tf` - Module variables
- `modules/opensearch_container/outputs.tf` - Module outputs
- `OPENSEARCH_CONTAINER_SETUP.md` - Detailed setup documentation

#### Modified Files
- `envs/dev/main.tf` - Commented out AWS OpenSearch, added containerized version
- `envs/dev/outputs.tf` - Updated outputs for containerized OpenSearch
- `modules/ecs_service/outputs.tf` - Added cluster_id output
- `modules/ecs_service/variables.tf` - Made opensearch_domain_arn nullable

## Next Steps

### 1. Deploy Infrastructure

```bash
cd envs/dev
terraform init
terraform plan  # Review changes
terraform apply
```

### 2. Configure Backend Environment Variables

Update your backend ECS task definition or environment variables to include:

```bash
OPENSEARCH_HOST=<opensearch-endpoint>
OPENSEARCH_PORT=9200
OPENSEARCH_USE_SSL=false
OPENSEARCH_VERIFY_CERTS=false
```

**Finding the OpenSearch Endpoint:**

After deployment, you'll need to determine the OpenSearch service endpoint. Options:

#### Option A: Use ECS Service Discovery (Recommended)

Enable service discovery in the OpenSearch container module (future enhancement) or configure it manually:

```bash
# Get service discovery endpoint
aws servicediscovery list-services --region <region>
```

#### Option B: Use Private IP (Temporary)

Get the OpenSearch task's private IP:

```bash
# List OpenSearch tasks
aws ecs list-tasks \
  --cluster <cluster-name> \
  --service-name <name>-opensearch-service \
  --region <region>

# Get task details (including private IP)
aws ecs describe-tasks \
  --cluster <cluster-name> \
  --tasks <task-id> \
  --region <region>
```

#### Option C: Update Terraform Outputs

Add a data source or output to expose the OpenSearch service endpoint automatically (future enhancement).

### 3. Update Backend Service

After getting the OpenSearch endpoint, update your backend service:

1. **Via Terraform** (if using app_environment variable):
   ```hcl
   app_environment = {
     OPENSEARCH_HOST = "<opensearch-endpoint>"
     OPENSEARCH_PORT = "9200"
     OPENSEARCH_USE_SSL = "false"
     OPENSEARCH_VERIFY_CERTS = "false"
   }
   ```

2. **Via ECS Console/CLI**:
   - Update the task definition environment variables
   - Force new deployment

### 4. Verify Connection

Test the OpenSearch connection from your backend:

```bash
# From backend container via ECS Exec
aws ecs execute-command \
  --cluster <cluster-name> \
  --task <backend-task-id> \
  --container <backend-container-name> \
  --interactive \
  --command "curl http://<opensearch-endpoint>:9200/_cluster/health"
```

## Important Notes

⚠️ **Security**: OpenSearch security is currently disabled. This is fine for development but should be enabled for production.

⚠️ **Persistence**: OpenSearch data is stored in the container. If the task stops, data is lost unless you:
- Add EFS volume for persistence (recommended)
- Configure periodic backups

⚠️ **Single Instance**: Currently configured as single-node. For production, consider:
- Multiple instances with proper cluster configuration
- Load balancing
- High availability setup

## Rollback Instructions

If you need to rollback to AWS OpenSearch Service:

1. Uncomment the `module "opensearch"` block in `envs/dev/main.tf`
2. Comment out `module "opensearch_container"`
3. Update `module.ecs_service`:
   ```hcl
   opensearch_domain_arn = module.opensearch.domain_arn
   enable_opensearch_access = true
   ```
4. Run `terraform apply`

## Future Enhancements

1. **Service Discovery**: Add AWS Cloud Map for stable DNS names
2. **Persistence**: Add EFS volume for data persistence
3. **Security**: Enable OpenSearch security plugin
4. **Dashboards**: Deploy OpenSearch Dashboards container
5. **Monitoring**: Add CloudWatch metrics and alarms
6. **Auto-scaling**: Configure ECS auto-scaling for OpenSearch

## Questions or Issues?

Refer to `OPENSEARCH_CONTAINER_SETUP.md` for detailed documentation, troubleshooting, and advanced configuration options.







