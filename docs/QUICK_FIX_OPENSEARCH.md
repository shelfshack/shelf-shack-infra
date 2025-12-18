# Quick Fix: OpenSearch Connection Error

## Problem
The backend is trying to connect to `localhost:443` (HTTPS) but OpenSearch container is running on a different IP with HTTP on port 9200.

## Solution

### Step 1: Get OpenSearch Service Endpoint

Run this command to get the OpenSearch container's private IP:

```bash
cd shelfshack-infra
./scripts/get_opensearch_endpoint.sh shelfshack-dev-cluster shelfshack-dev-opensearch-service us-east-1
```

Or manually:

```bash
# Get the task ARN
TASK_ARN=$(aws ecs list-tasks \
  --cluster shelfshack-dev-cluster \
  --service-name shelfshack-dev-opensearch-service \
  --region us-east-1 \
  --query 'taskArns[0]' \
  --output text)

# Get ENI ID
ENI_ID=$(aws ecs describe-tasks \
  --cluster shelfshack-dev-cluster \
  --tasks $TASK_ARN \
  --region us-east-1 \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
  --output text)

# Get private IP
PRIVATE_IP=$(aws ec2 describe-network-interfaces \
  --network-interface-ids $ENI_ID \
  --region us-east-1 \
  --query 'NetworkInterfaces[0].PrivateIpAddress' \
  --output text)

echo "OpenSearch IP: $PRIVATE_IP"
```

### Step 2: Update Backend Environment Variables

You need to update your backend ECS task definition with these environment variables:

```bash
OPENSEARCH_HOST=<PRIVATE_IP_FROM_STEP_1>
OPENSEARCH_PORT=9200
OPENSEARCH_USE_SSL=false
OPENSEARCH_VERIFY_CERTS=false
```

#### Option A: Update via Terraform

If you're using Terraform to manage environment variables, update `envs/dev/main.tf`:

```hcl
app_environment = {
  # ... other variables ...
  OPENSEARCH_HOST = "<PRIVATE_IP>"
  OPENSEARCH_PORT = "9200"
  OPENSEARCH_USE_SSL = "false"
  OPENSEARCH_VERIFY_CERTS = "false"
}
```

Then run:
```bash
cd envs/dev
terraform apply
```

#### Option B: Update via AWS Console

1. Go to ECS Console → Clusters → `shelfshack-dev-cluster`
2. Click on `shelfshack-dev-service` (your backend service)
3. Click "Update" → "Modify task definition"
4. Add/update environment variables:
   - `OPENSEARCH_HOST` = `<PRIVATE_IP>`
   - `OPENSEARCH_PORT` = `9200`
   - `OPENSEARCH_USE_SSL` = `false`
   - `OPENSEARCH_VERIFY_CERTS` = `false`
5. Create new revision and update service

#### Option C: Update via AWS CLI

```bash
# Get current task definition
aws ecs describe-task-definition \
  --task-definition shelfshack-dev-task \
  --region us-east-1 \
  --query 'taskDefinition' > task-def.json

# Edit task-def.json to add environment variables, then:

# Register new task definition
aws ecs register-task-definition \
  --cli-input-json file://task-def.json \
  --region us-east-1

# Update service
aws ecs update-service \
  --cluster shelfshack-dev-cluster \
  --service shelfshack-dev-service \
  --task-definition shelfshack-dev-task:<NEW_REVISION> \
  --region us-east-1
```

### Step 3: Verify OpenSearch is Running

Check if OpenSearch service is running:

```bash
aws ecs describe-services \
  --cluster shelfshack-dev-cluster \
  --services shelfshack-dev-opensearch-service \
  --region us-east-1 \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'
```

If `runningCount` is 0, check CloudWatch logs:
```bash
aws logs tail /ecs/shelfshack-dev-opensearch/opensearch --follow --region us-east-1
```

### Step 4: Test Connection

After updating environment variables, test the connection from backend:

```bash
# Get backend task ID
BACKEND_TASK=$(aws ecs list-tasks \
  --cluster shelfshack-dev-cluster \
  --service-name shelfshack-dev-service \
  --region us-east-1 \
  --query 'taskArns[0]' \
  --output text)

# Execute command in backend container
aws ecs execute-command \
  --cluster shelfshack-dev-cluster \
  --task $BACKEND_TASK \
  --container shelfshack-dev \
  --interactive \
  --command "curl http://$PRIVATE_IP:9200/_cluster/health"
```

## Important Notes

⚠️ **Private IP Changes**: The private IP will change if the OpenSearch task restarts. For a permanent solution, consider:

1. **Service Discovery** (Recommended): Set up AWS Service Discovery for stable DNS names
2. **Load Balancer**: Use an internal ALB/NLB for OpenSearch
3. **Update Script**: Automate updating the backend environment variable when IP changes

## Long-term Solution

For a more permanent solution, we should set up service discovery. See `OPENSEARCH_CONTAINER_SETUP.md` for details on enabling service discovery.







