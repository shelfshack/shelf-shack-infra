# Terraform Verification Checklist

Use this checklist to verify that all resources created by Terraform are properly configured and functioning.

## 📋 Pre-Deployment Checklist

### ✅ Manual Resources (Must exist before `terraform apply`)
- [ ] **S3 Bucket**: `shelfshack-terraform-state` (for Terraform state)
- [ ] **DynamoDB Table**: `shelfshack-terraform-locks` (for state locking)
- [ ] **S3 Bucket**: `shelfshack-dev-uploads` (for application uploads)
- [ ] **Secrets Manager Secrets**: All secrets referenced in `app_secrets` exist
- [ ] **Route53 Hosted Zone**: (if using custom domain)

---

## 🏗️ Networking Resources

### VPC & Subnets
```bash
# Verify VPC
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=shelfshack-dev-vpc" --query 'Vpcs[0].{VpcId:VpcId,CidrBlock:CidrBlock}'

# Verify Subnets
aws ec2 describe-subnets --filters "Name=tag:Name,Values=shelfshack-dev-*" --query 'Subnets[*].{Name:Tags[?Key==`Name`].Value|[0],SubnetId:SubnetId,Cidr:CidrBlock,Az:AvailabilityZone}'
```

- [ ] **VPC**: `shelfshack-dev-vpc` exists with CIDR `10.0.0.0/16`
- [ ] **Public Subnets**: 2 subnets in different AZs (10.0.0.0/24, 10.0.1.0/24)
- [ ] **Private Subnets**: 2 subnets in different AZs (10.0.10.0/24, 10.0.11.0/24)
- [ ] **Internet Gateway**: `shelfshack-dev-igw` attached to VPC
- [ ] **NAT Gateway**: `shelfshack-dev-nat` exists with Elastic IP
- [ ] **Route Tables**: Public and Private route tables configured correctly
- [ ] **VPC Endpoints**: SSM, SSM Messages, EC2 Messages endpoints exist (if enabled)

### Security Groups
```bash
# List all security groups
aws ec2 describe-security-groups --filters "Name=tag:Name,Values=shelfshack-dev-*" --query 'SecurityGroups[*].{Name:GroupName,Id:GroupId,Description:Description}'
```

- [ ] **ALB Security Group**: `shelfshack-dev-alb-sg` (if ALB enabled)
- [ ] **ECS Service Security Group**: `shelfshack-dev-svc-sg`
- [ ] **RDS Security Group**: Allows port 5432 from ECS service
- [ ] **OpenSearch EC2 Security Group**: Allows ports 9200, 9600 from ECS service
- [ ] **SSM Endpoints Security Group**: `shelfshack-dev-ssm-endpoints` (if enabled)

---

## 🚀 ECS Resources

### ECS Cluster & Service
```bash
# Get cluster info
aws ecs describe-clusters --clusters shelfshack-dev-cluster

# Get service info
aws ecs describe-services --cluster shelfshack-dev-cluster --services shelfshack-dev-service

# List running tasks
aws ecs list-tasks --cluster shelfshack-dev-cluster --service-name shelfshack-dev-service
```

- [ ] **ECS Cluster**: `shelfshack-dev-cluster` exists
- [ ] **ECS Service**: `shelfshack-dev-service` is running
- [ ] **Task Definition**: `shelfshack-dev-task` exists
- [ ] **Running Tasks**: At least 1 task is running (check `desired_count`)
- [ ] **Task Status**: All tasks are in `RUNNING` state
- [ ] **Service Health**: Service is stable (no constant restarts)

### ECS Task Details
```bash
# Get task details
TASK_ARN=$(aws ecs list-tasks --cluster shelfshack-dev-cluster --service-name shelfshack-dev-service --query 'taskArns[0]' --output text)
aws ecs describe-tasks --cluster shelfshack-dev-cluster --tasks $TASK_ARN
```

- [ ] **Task CPU**: 1024 units
- [ ] **Task Memory**: 2048 MB
- [ ] **Container Image**: Correct ECR image with tag
- [ ] **Environment Variables**: All required env vars are set
- [ ] **Secrets**: All secrets are accessible
- [ ] **Network Mode**: `awsvpc`
- [ ] **Public IP**: Task has public IP (if ALB disabled)

### Load Balancer (if enabled)
```bash
# Get ALB info
aws elbv2 describe-load-balancers --names shelfshack-dev-alb

# Get target group health
aws elbv2 describe-target-health --target-group-arn <target-group-arn>
```

- [ ] **ALB**: `shelfshack-dev-alb` exists (if `enable_load_balancer = true`)
- [ ] **Target Group**: `shelfshack-dev-tg` exists
- [ ] **Target Health**: All targets are healthy
- [ ] **Listeners**: HTTP (and HTTPS if enabled) listeners configured
- [ ] **ALB DNS**: DNS name is accessible

---

## 🗄️ Database Resources

### RDS PostgreSQL
```bash
# Get RDS instance info
aws rds describe-db-instances --db-instance-identifier shelfshack-dev-postgres
```

- [ ] **RDS Instance**: `shelfshack-dev-postgres` exists
- [ ] **Engine Version**: PostgreSQL 17.6
- [ ] **Storage**: 20GB allocated
- [ ] **Multi-AZ**: Configured as per `db_multi_az` setting
- [ ] **Public Access**: `db_publicly_accessible` setting is correct
- [ ] **Security Group**: Allows port 5432 from ECS service
- [ ] **Endpoint**: Database endpoint is accessible from ECS tasks
- [ ] **Connection**: Application can connect to database

### Database Connectivity Test
```bash
# Test from ECS task (using ECS Exec)
aws ecs execute-command \
  --cluster shelfshack-dev-cluster \
  --task <task-id> \
  --container shelfshack-dev \
  --interactive \
  --command "psql $DATABASE_URL -c 'SELECT version();'"
```

- [ ] **Database Connection**: ECS tasks can connect to RDS
- [ ] **Database Name**: Correct database name exists
- [ ] **Credentials**: Master username/password work

---

## 🔍 OpenSearch Resources

### OpenSearch EC2
```bash
# Get EC2 instance info
aws ec2 describe-instances --filters "Name=tag:Name,Values=shelfshack-dev-opensearch-ec2*" --query 'Reservations[*].Instances[*].{InstanceId:InstanceId,State:State.Name,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress}'

# Get OpenSearch endpoint
terraform output opensearch_ec2_endpoint
```

- [ ] **EC2 Instance**: OpenSearch EC2 instance exists
- [ ] **Instance Type**: `m7i-flex.large` (or configured type)
- [ ] **Instance State**: `running`
- [ ] **Docker Container**: OpenSearch container is running
- [ ] **Port 9200**: OpenSearch HTTP API is accessible
- [ ] **Port 9600**: Performance analyzer is accessible
- [ ] **Security Group**: Allows ports 9200, 9600 from ECS service
- [ ] **Health Check**: OpenSearch cluster health is `green` or `yellow`

### OpenSearch Connectivity
```bash
# Test OpenSearch from ECS task
OPENSEARCH_IP=$(terraform output -raw opensearch_ec2_host)
aws ecs execute-command \
  --cluster shelfshack-dev-cluster \
  --task <task-id> \
  --container shelfshack-dev \
  --interactive \
  --command "curl http://${OPENSEARCH_IP}:9200/_cluster/health"
```

- [ ] **OpenSearch Connection**: ECS tasks can connect to OpenSearch
- [ ] **Cluster Health**: Cluster health endpoint returns status
- [ ] **Environment Variables**: `OPENSEARCH_HOST`, `OPENSEARCH_PORT` are set

---

## 🌐 API Gateway Resources

### HTTP API Gateway
```bash
# Get HTTP API Gateway info
aws apigatewayv2 get-apis --query 'Items[?Name==`shelfshack-dev-backend`]'

# Get API Gateway endpoint
terraform output http_api_gateway_endpoint
```

- [ ] **HTTP API Gateway**: `shelfshack-dev-backend` exists
- [ ] **Stage**: `development` stage exists
- [ ] **Routes**: `ANY /{proxy+}` and `ANY /` routes exist
- [ ] **Integration**: Integration points to ECS service (dynamic IP)
- [ ] **CORS**: CORS configuration is set (if needed)
- [ ] **Endpoint**: API Gateway endpoint is accessible
- [ ] **Proxy**: Requests to API Gateway proxy to ECS service correctly

### WebSocket API Gateway
```bash
# Get WebSocket API Gateway info
aws apigatewayv2 get-apis --query 'Items[?Name==`shelfshack-dev-websocket`]'

# Get WebSocket endpoint
terraform output websocket_api_endpoint
```

- [ ] **WebSocket API Gateway**: `shelfshack-dev-websocket` exists
- [ ] **Stage**: `development` stage exists
- [ ] **Routes**: `$connect`, `$disconnect`, `$default` routes exist
- [ ] **Integration**: Integration points to Lambda function
- [ ] **Endpoint**: WebSocket endpoint is accessible (wss://...)

---

## ⚡ Lambda Resources

### WebSocket Lambda
```bash
# Get Lambda function info
aws lambda get-function --function-name shelfshack-dev-websocket-proxy

# Test Lambda
aws lambda invoke --function-name shelfshack-dev-websocket-proxy --payload '{}' response.json
```

- [ ] **Lambda Function**: `shelfshack-dev-websocket-proxy` exists
- [ ] **Runtime**: Correct runtime (Python 3.x)
- [ ] **Handler**: Handler function is correct
- [ ] **Environment Variables**: `BACKEND_URL` is set correctly
- [ ] **IAM Role**: Lambda has execution role with correct permissions
- [ ] **API Gateway Integration**: Lambda is integrated with WebSocket API
- [ ] **DynamoDB Access**: Lambda can read/write to connections table

---

## 📊 DynamoDB Resources

### WebSocket Connections Table
```bash
# Get DynamoDB table info
aws dynamodb describe-table --table-name shelfshack-dev-websocket-connections
```

- [ ] **DynamoDB Table**: `shelfshack-dev-websocket-connections` exists
- [ ] **Table Status**: Table is `ACTIVE`
- [ ] **Primary Key**: Connection ID is the primary key
- [ ] **Lambda Permissions**: Lambda has read/write permissions

---

## 💾 Storage Resources

### ECR Repository
```bash
# Get ECR repository info
aws ecr describe-repositories --repository-names shelfshack-dev-repo
```

- [ ] **ECR Repository**: `shelfshack-dev-repo` exists
- [ ] **Repository URI**: Repository URI is correct
- [ ] **Image Scanning**: Image scanning is enabled (if configured)
- [ ] **Lifecycle Policy**: Lifecycle policy is set (if configured)
- [ ] **Images**: At least one image is pushed to repository

### S3 Buckets
```bash
# Verify S3 buckets
aws s3 ls | grep shelfshack
```

- [ ] **S3 Upload Bucket**: `shelfshack-dev-uploads` exists
- [ ] **S3 Bucket Policy**: Bucket policy allows public read/write (if configured)
- [ ] **S3 CORS**: CORS configuration is set
- [ ] **S3 Encryption**: Encryption is enabled
- [ ] **S3 State Bucket**: `shelfshack-terraform-state` exists (manual)

---

## 🔐 IAM Resources

### Deploy Role
```bash
# Get deploy role info
aws iam get-role --role-name shelfshackDeployRole

# List role policies
aws iam list-role-policies --role-name shelfshackDeployRole
aws iam list-attached-role-policies --role-name shelfshackDeployRole
```

- [ ] **Deploy Role**: `shelfshackDeployRole` exists
- [ ] **Assume Role Policy**: Allows GitHub OIDC and user assume
- [ ] **Inline Policy**: Consolidated policy is attached
- [ ] **Managed Policies**: 5 managed policies are attached:
  - [ ] AmazonEC2ContainerRegistryPowerUser
  - [ ] AmazonECSTaskExecutionRolePolicy
  - [ ] CloudWatchLogsFullAccess
  - [ ] AmazonECS_FullAccess
  - [ ] ElasticLoadBalancingFullAccess

### Execution Role
```bash
# Get execution role info
aws iam get-role --role-name shelfshack-dev-execution-role
```

- [ ] **Execution Role**: `shelfshack-dev-execution-role` exists
- [ ] **Assume Role Policy**: Allows ECS tasks to assume role
- [ ] **Secrets Policy**: Policy allows access to all secrets in `app_secrets`
- [ ] **ECR Access**: Can pull images from ECR repository

### Task Role
```bash
# Get task role info
aws iam get-role --role-name shelfshack-dev-task-role

# List task role policies
aws iam list-role-policies --role-name shelfshack-dev-task-role
```

- [ ] **Task Role**: `shelfshack-dev-task-role` exists
- [ ] **Assume Role Policy**: Allows ECS tasks to assume role
- [ ] **S3 Policy**: Policy allows access to `shelfshack-dev-uploads` bucket
- [ ] **Secrets Policy**: Policy allows access to secrets (if configured)
- [ ] **OpenSearch Policy**: Policy allows OpenSearch access (if enabled)

---

## 📝 CloudWatch Resources

### Log Groups
```bash
# List log groups
aws logs describe-log-groups --log-group-name-prefix "/ecs/shelfshack-dev"
aws logs describe-log-groups --log-group-name-prefix "/aws/ecs/executioncommand"
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/shelfshack-dev"
```

- [ ] **ECS Log Group**: `/ecs/shelfshack-dev` exists
- [ ] **ECS Exec Log Group**: `/aws/ecs/executioncommand/shelfshack-dev-cluster` exists
- [ ] **Lambda Log Group**: `/aws/lambda/shelfshack-dev-websocket-proxy` exists
- [ ] **Log Retention**: Retention period is set correctly
- [ ] **Logs Streaming**: Logs are being written to CloudWatch

---

## 🌐 Route53 Resources (Optional)

### DNS Records
```bash
# Get Route53 records (if configured)
aws route53 list-resource-record-sets --hosted-zone-id <zone-id>
```

- [ ] **API Record**: `api.shelfshack.com` points to ALB (if configured)
- [ ] **Record Type**: A record (alias to ALB)
- [ ] **Health Check**: Record evaluates target health

---

## 🔗 Connectivity Tests

### End-to-End Tests
```bash
# Test HTTP API Gateway
HTTP_API_URL=$(terraform output -raw http_api_gateway_endpoint)
curl -v ${HTTP_API_URL}/health

# Test WebSocket API Gateway
WS_API_URL=$(terraform output -raw websocket_api_endpoint)
# Use wscat or similar tool to test WebSocket connection

# Test ECS Service directly (if public IP)
ECS_IP=$(terraform output -raw ecs_service_public_ip)
curl http://${ECS_IP}:8000/health

# Test OpenSearch
OPENSEARCH_IP=$(terraform output -raw opensearch_ec2_host)
curl http://${OPENSEARCH_IP}:9200/_cluster/health
```

- [ ] **HTTP API Gateway**: Returns 200 OK for health check
- [ ] **WebSocket API Gateway**: Can establish WebSocket connection
- [ ] **ECS Service Direct**: Service responds on port 8000
- [ ] **OpenSearch**: Cluster health endpoint returns status
- [ ] **Database**: Application can query database
- [ ] **S3 Upload**: Application can upload files to S3

---

## 🔍 Security Verification

### Security Groups
- [ ] **ALB Security Group**: Only allows HTTP/HTTPS from internet
- [ ] **ECS Security Group**: Only allows traffic from ALB (if ALB enabled) or public (if ALB disabled)
- [ ] **RDS Security Group**: Only allows port 5432 from ECS service
- [ ] **OpenSearch Security Group**: Only allows ports 9200, 9600 from ECS service
- [ ] **No Open Ports**: No unnecessary ports are open

### IAM Permissions
- [ ] **Least Privilege**: All IAM roles follow least privilege principle
- [ ] **No Wildcards**: Policies don't use `*` for resources (where possible)
- [ ] **Secrets Access**: Only required secrets are accessible
- [ ] **S3 Access**: Task role only has access to required S3 bucket

---

## 📊 Resource Counts

### Expected Resource Counts
```bash
# Count resources by type
echo "VPCs: $(aws ec2 describe-vpcs --filters 'Name=tag:Name,Values=shelfshack-dev-*' --query 'length(Vpcs)')"
echo "Subnets: $(aws ec2 describe-subnets --filters 'Name=tag:Name,Values=shelfshack-dev-*' --query 'length(Subnets)')"
echo "Security Groups: $(aws ec2 describe-security-groups --filters 'Name=tag:Name,Values=shelfshack-dev-*' --query 'length(SecurityGroups)')"
echo "EC2 Instances: $(aws ec2 describe-instances --filters 'Name=tag:Name,Values=shelfshack-dev-*' 'Name=instance-state-name,Values=running' --query 'length(Reservations[*].Instances[])')"
echo "ECS Clusters: $(aws ecs list-clusters --query 'length(clusterArns[?contains(@, `shelfshack-dev`)])')"
echo "RDS Instances: $(aws rds describe-db-instances --query 'length(DBInstances[?contains(DBInstanceIdentifier, `shelfshack-dev`)])')"
echo "API Gateways: $(aws apigatewayv2 get-apis --query 'length(Items[?contains(Name, `shelfshack-dev`)])')"
echo "Lambda Functions: $(aws lambda list-functions --query 'length(Functions[?contains(FunctionName, `shelfshack-dev`)])')"
echo "DynamoDB Tables: $(aws dynamodb list-tables --query 'length(TableNames[?contains(@, `shelfshack-dev`)])')"
```

- [ ] **VPCs**: 1
- [ ] **Subnets**: 4 (2 public + 2 private)
- [ ] **Security Groups**: 5-7 (depending on configuration)
- [ ] **EC2 Instances**: 1 (OpenSearch EC2, if enabled)
- [ ] **ECS Clusters**: 1
- [ ] **ECS Services**: 1
- [ ] **RDS Instances**: 1
- [ ] **API Gateways**: 2 (HTTP + WebSocket)
- [ ] **Lambda Functions**: 1
- [ ] **DynamoDB Tables**: 1

---

## 🧪 Functional Tests

### Application Functionality
- [ ] **API Endpoints**: All API endpoints respond correctly
- [ ] **Database Queries**: Database queries work
- [ ] **Search**: OpenSearch search functionality works
- [ ] **File Upload**: File upload to S3 works
- [ ] **WebSocket**: WebSocket connections work
- [ ] **Authentication**: Authentication/authorization works
- [ ] **Error Handling**: Error handling and fallbacks work

### Performance Tests
- [ ] **Response Time**: API response times are acceptable
- [ ] **Concurrent Requests**: Service handles concurrent requests
- [ ] **Database Performance**: Database queries are performant
- [ ] **Search Performance**: OpenSearch queries are fast

---

## 📈 Monitoring & Alarms

### CloudWatch Metrics
```bash
# Check CloudWatch metrics
aws cloudwatch list-metrics --namespace AWS/ECS --dimensions Name=ServiceName,Value=shelfshack-dev-service
```

- [ ] **ECS Metrics**: CPU, Memory, Task count metrics are available
- [ ] **RDS Metrics**: Database metrics are available
- [ ] **Lambda Metrics**: Lambda invocation metrics are available
- [ ] **API Gateway Metrics**: Request count, latency metrics are available
- [ ] **Alarms**: CloudWatch alarms are configured (if needed)

---

## 🔄 Terraform State Verification

### State File
```bash
# Verify Terraform state
cd envs/dev
terraform state list
```

- [ ] **State File**: State file exists in S3 backend
- [ ] **State Lock**: DynamoDB table is used for locking
- [ ] **State Resources**: All resources are in state
- [ ] **No Drift**: `terraform plan` shows no unexpected changes

---

## ✅ Quick Verification Script

Save this as `scripts/verify_infrastructure.sh`:

```bash
#!/bin/bash
set -e

echo "🔍 Verifying ShelfShack Infrastructure..."
echo ""

# Check VPC
echo "📡 Checking VPC..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=shelfshack-dev-vpc" --query 'Vpcs[0].VpcId' --output text)
if [ "$VPC_ID" != "None" ] && [ -n "$VPC_ID" ]; then
  echo "✅ VPC exists: $VPC_ID"
else
  echo "❌ VPC not found"
fi

# Check ECS Cluster
echo ""
echo "🚀 Checking ECS Cluster..."
CLUSTER_STATUS=$(aws ecs describe-clusters --clusters shelfshack-dev-cluster --query 'clusters[0].status' --output text)
if [ "$CLUSTER_STATUS" == "ACTIVE" ]; then
  echo "✅ ECS Cluster is ACTIVE"
else
  echo "❌ ECS Cluster status: $CLUSTER_STATUS"
fi

# Check ECS Service
echo ""
echo "📦 Checking ECS Service..."
SERVICE_STATUS=$(aws ecs describe-services --cluster shelfshack-dev-cluster --services shelfshack-dev-service --query 'services[0].status' --output text)
if [ "$SERVICE_STATUS" == "ACTIVE" ]; then
  RUNNING_COUNT=$(aws ecs describe-services --cluster shelfshack-dev-cluster --services shelfshack-dev-service --query 'services[0].runningCount' --output text)
  DESIRED_COUNT=$(aws ecs describe-services --cluster shelfshack-dev-cluster --services shelfshack-dev-service --query 'services[0].desiredCount' --output text)
  echo "✅ ECS Service is ACTIVE (Running: $RUNNING_COUNT/$DESIRED_COUNT)"
else
  echo "❌ ECS Service status: $SERVICE_STATUS"
fi

# Check RDS
echo ""
echo "🗄️ Checking RDS..."
RDS_STATUS=$(aws rds describe-db-instances --db-instance-identifier shelfshack-dev-postgres --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$RDS_STATUS" == "available" ]; then
  echo "✅ RDS is available"
else
  echo "❌ RDS status: $RDS_STATUS"
fi

# Check OpenSearch EC2
echo ""
echo "🔍 Checking OpenSearch EC2..."
OPENSEARCH_INSTANCE=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=shelfshack-dev-opensearch-ec2*" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$OPENSEARCH_INSTANCE" != "None" ] && [ -n "$OPENSEARCH_INSTANCE" ] && [ "$OPENSEARCH_INSTANCE" != "NOT_FOUND" ]; then
  echo "✅ OpenSearch EC2 instance is running: $OPENSEARCH_INSTANCE"
else
  echo "❌ OpenSearch EC2 instance not found or not running"
fi

# Check API Gateways
echo ""
echo "🌐 Checking API Gateways..."
HTTP_API=$(aws apigatewayv2 get-apis --query 'Items[?Name==`shelfshack-dev-backend`].ApiId' --output text)
WS_API=$(aws apigatewayv2 get-apis --query 'Items[?Name==`shelfshack-dev-websocket`].ApiId' --output text)
if [ -n "$HTTP_API" ] && [ "$HTTP_API" != "None" ]; then
  echo "✅ HTTP API Gateway exists: $HTTP_API"
else
  echo "❌ HTTP API Gateway not found"
fi
if [ -n "$WS_API" ] && [ "$WS_API" != "None" ]; then
  echo "✅ WebSocket API Gateway exists: $WS_API"
else
  echo "❌ WebSocket API Gateway not found"
fi

# Check Lambda
echo ""
echo "⚡ Checking Lambda..."
LAMBDA_EXISTS=$(aws lambda get-function --function-name shelfshack-dev-websocket-proxy --query 'Configuration.FunctionName' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$LAMBDA_EXISTS" != "NOT_FOUND" ]; then
  echo "✅ Lambda function exists: $LAMBDA_EXISTS"
else
  echo "❌ Lambda function not found"
fi

# Check IAM Roles
echo ""
echo "🔐 Checking IAM Roles..."
DEPLOY_ROLE=$(aws iam get-role --role-name shelfshackDeployRole --query 'Role.RoleName' --output text 2>/dev/null || echo "NOT_FOUND")
EXEC_ROLE=$(aws iam get-role --role-name shelfshack-dev-execution-role --query 'Role.RoleName' --output text 2>/dev/null || echo "NOT_FOUND")
TASK_ROLE=$(aws iam get-role --role-name shelfshack-dev-task-role --query 'Role.RoleName' --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$DEPLOY_ROLE" != "NOT_FOUND" ]; then
  echo "✅ Deploy Role exists: $DEPLOY_ROLE"
else
  echo "❌ Deploy Role not found"
fi
if [ "$EXEC_ROLE" != "NOT_FOUND" ]; then
  echo "✅ Execution Role exists: $EXEC_ROLE"
else
  echo "❌ Execution Role not found"
fi
if [ "$TASK_ROLE" != "NOT_FOUND" ]; then
  echo "✅ Task Role exists: $TASK_ROLE"
else
  echo "❌ Task Role not found"
fi

echo ""
echo "✅ Verification complete!"
```

---

## 🎯 Post-Deployment Verification

After running `terraform apply`, verify:

1. **Terraform Outputs**: Run `terraform output` and verify all outputs
2. **Resource Tags**: All resources have correct tags (Project, Environment, ManagedBy)
3. **Cost**: Check AWS Cost Explorer for unexpected charges
4. **Alarms**: Set up CloudWatch alarms for critical metrics
5. **Backup**: Verify RDS backups are configured
6. **Documentation**: Update any documentation with actual resource names/IDs

---

## 🚨 Common Issues to Check

- [ ] **ECS Tasks Restarting**: Check CloudWatch logs for errors
- [ ] **Database Connection Issues**: Verify security group rules
- [ ] **OpenSearch Not Accessible**: Check container status and security groups
- [ ] **API Gateway 502 Errors**: Verify ECS service is healthy
- [ ] **Lambda Timeouts**: Check Lambda timeout and backend URL
- [ ] **S3 Access Denied**: Verify IAM policies and bucket policies
- [ ] **Secrets Not Found**: Verify secret ARNs are correct

---

## 📞 Support Commands

```bash
# Get all resource IDs
terraform output

# Get ECS task public IP
terraform output ecs_service_public_ip

# Get backend URL
terraform output backend_url

# Get API Gateway endpoints
terraform output http_api_gateway_endpoint
terraform output websocket_api_endpoint

# Get OpenSearch endpoint
terraform output opensearch_ec2_endpoint

# Get RDS endpoint
terraform output rds_endpoint
```

