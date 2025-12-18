#!/bin/bash
# Infrastructure Verification Script
# Verifies all Terraform-created resources are in place and functioning

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Verifying ShelfShack Infrastructure...${NC}"
echo ""

# Function to check resource
check_resource() {
    local name=$1
    local command=$2
    local query=$3
    
    result=$(eval "$command" 2>/dev/null || echo "NOT_FOUND")
    if [ "$result" != "NOT_FOUND" ] && [ "$result" != "None" ] && [ -n "$result" ]; then
        echo -e "${GREEN}✅ $name${NC}: $result"
        return 0
    else
        echo -e "${RED}❌ $name${NC}: Not found"
        return 1
    fi
}

# Check VPC
echo -e "${BLUE}📡 Networking Resources${NC}"
check_resource "VPC" \
    "aws ec2 describe-vpcs --filters 'Name=tag:Name,Values=shelfshack-dev-vpc' --query 'Vpcs[0].VpcId' --output text" \
    "VpcId"

# Check Subnets
PUBLIC_SUBNETS=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=shelfshack-dev-public-*" --query 'length(Subnets)' --output text)
PRIVATE_SUBNETS=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=shelfshack-dev-private-*" --query 'length(Subnets)' --output text)
echo -e "${GREEN}✅ Public Subnets${NC}: $PUBLIC_SUBNETS"
echo -e "${GREEN}✅ Private Subnets${NC}: $PRIVATE_SUBNETS"

# Check Internet Gateway
IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=shelfshack-dev-igw" --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$IGW_ID" != "NOT_FOUND" ] && [ -n "$IGW_ID" ]; then
    echo -e "${GREEN}✅ Internet Gateway${NC}: $IGW_ID"
else
    echo -e "${RED}❌ Internet Gateway${NC}: Not found"
fi

# Check NAT Gateway
NAT_ID=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=shelfshack-dev-nat" --query 'NatGateways[0].NatGatewayId' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$NAT_ID" != "NOT_FOUND" ] && [ -n "$NAT_ID" ]; then
    echo -e "${GREEN}✅ NAT Gateway${NC}: $NAT_ID"
else
    echo -e "${YELLOW}⚠️  NAT Gateway${NC}: Not found (may be disabled)"
fi

echo ""
echo -e "${BLUE}🚀 ECS Resources${NC}"

# Check ECS Cluster
CLUSTER_STATUS=$(aws ecs describe-clusters --clusters shelfshack-dev-cluster --query 'clusters[0].status' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$CLUSTER_STATUS" == "ACTIVE" ]; then
    echo -e "${GREEN}✅ ECS Cluster${NC}: ACTIVE"
else
    echo -e "${RED}❌ ECS Cluster${NC}: $CLUSTER_STATUS"
fi

# Check ECS Service
SERVICE_INFO=$(aws ecs describe-services --cluster shelfshack-dev-cluster --services shelfshack-dev-service --query 'services[0]' 2>/dev/null || echo "{}")
SERVICE_STATUS=$(echo "$SERVICE_INFO" | jq -r '.status // "NOT_FOUND"')
RUNNING_COUNT=$(echo "$SERVICE_INFO" | jq -r '.runningCount // 0')
DESIRED_COUNT=$(echo "$SERVICE_INFO" | jq -r '.desiredCount // 0')

if [ "$SERVICE_STATUS" == "ACTIVE" ]; then
    echo -e "${GREEN}✅ ECS Service${NC}: ACTIVE (Running: $RUNNING_COUNT/$DESIRED_COUNT)"
    if [ "$RUNNING_COUNT" -lt "$DESIRED_COUNT" ]; then
        echo -e "${YELLOW}⚠️  Warning: Not all tasks are running${NC}"
    fi
else
    echo -e "${RED}❌ ECS Service${NC}: $SERVICE_STATUS"
fi

# Check ECS Tasks
TASK_COUNT=$(aws ecs list-tasks --cluster shelfshack-dev-cluster --service-name shelfshack-dev-service --query 'length(taskArns)' --output text 2>/dev/null || echo "0")
echo -e "${GREEN}✅ Running Tasks${NC}: $TASK_COUNT"

echo ""
echo -e "${BLUE}🗄️ Database Resources${NC}"

# Check RDS
RDS_STATUS=$(aws rds describe-db-instances --db-instance-identifier shelfshack-dev-postgres --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$RDS_STATUS" == "available" ]; then
    RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier shelfshack-dev-postgres --query 'DBInstances[0].Endpoint.Address' --output text 2>/dev/null)
    echo -e "${GREEN}✅ RDS PostgreSQL${NC}: $RDS_STATUS"
    echo -e "   Endpoint: $RDS_ENDPOINT"
else
    echo -e "${RED}❌ RDS PostgreSQL${NC}: $RDS_STATUS"
fi

echo ""
echo -e "${BLUE}🔍 OpenSearch Resources${NC}"

# Check OpenSearch EC2
OPENSEARCH_INSTANCE=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=shelfshack-dev-opensearch-ec2*" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$OPENSEARCH_INSTANCE" != "NOT_FOUND" ] && [ -n "$OPENSEARCH_INSTANCE" ]; then
    OPENSEARCH_IP=$(aws ec2 describe-instances --instance-ids "$OPENSEARCH_INSTANCE" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text 2>/dev/null)
    echo -e "${GREEN}✅ OpenSearch EC2${NC}: $OPENSEARCH_INSTANCE"
    echo -e "   Private IP: $OPENSEARCH_IP"
else
    echo -e "${YELLOW}⚠️  OpenSearch EC2${NC}: Not found or not running (may be disabled)"
fi

echo ""
echo -e "${BLUE}🌐 API Gateway Resources${NC}"

# Check HTTP API Gateway
HTTP_API=$(aws apigatewayv2 get-apis --query 'Items[?Name==`shelfshack-dev-backend`].ApiId' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$HTTP_API" != "NOT_FOUND" ] && [ -n "$HTTP_API" ]; then
    echo -e "${GREEN}✅ HTTP API Gateway${NC}: $HTTP_API"
    HTTP_ENDPOINT="https://${HTTP_API}.execute-api.us-east-1.amazonaws.com/development"
    echo -e "   Endpoint: $HTTP_ENDPOINT"
else
    echo -e "${RED}❌ HTTP API Gateway${NC}: Not found"
fi

# Check WebSocket API Gateway
WS_API=$(aws apigatewayv2 get-apis --query 'Items[?Name==`shelfshack-dev-websocket`].ApiId' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$WS_API" != "NOT_FOUND" ] && [ -n "$WS_API" ]; then
    echo -e "${GREEN}✅ WebSocket API Gateway${NC}: $WS_API"
    WS_ENDPOINT="wss://${WS_API}.execute-api.us-east-1.amazonaws.com/development"
    echo -e "   Endpoint: $WS_ENDPOINT"
else
    echo -e "${RED}❌ WebSocket API Gateway${NC}: Not found"
fi

echo ""
echo -e "${BLUE}⚡ Lambda Resources${NC}"

# Check Lambda
LAMBDA_EXISTS=$(aws lambda get-function --function-name shelfshack-dev-websocket-proxy --query 'Configuration.FunctionName' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$LAMBDA_EXISTS" != "NOT_FOUND" ]; then
    LAMBDA_STATUS=$(aws lambda get-function --function-name shelfshack-dev-websocket-proxy --query 'Configuration.State' --output text 2>/dev/null)
    echo -e "${GREEN}✅ Lambda Function${NC}: $LAMBDA_EXISTS ($LAMBDA_STATUS)"
else
    echo -e "${RED}❌ Lambda Function${NC}: Not found"
fi

echo ""
echo -e "${BLUE}📊 DynamoDB Resources${NC}"

# Check DynamoDB
DYNAMODB_STATUS=$(aws dynamodb describe-table --table-name shelfshack-dev-websocket-connections --query 'Table.TableStatus' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$DYNAMODB_STATUS" == "ACTIVE" ]; then
    echo -e "${GREEN}✅ DynamoDB Table${NC}: ACTIVE"
else
    echo -e "${RED}❌ DynamoDB Table${NC}: $DYNAMODB_STATUS"
fi

echo ""
echo -e "${BLUE}💾 Storage Resources${NC}"

# Check ECR
ECR_EXISTS=$(aws ecr describe-repositories --repository-names shelfshack-dev-repo --query 'repositories[0].repositoryUri' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$ECR_EXISTS" != "NOT_FOUND" ]; then
    echo -e "${GREEN}✅ ECR Repository${NC}: $ECR_EXISTS"
else
    echo -e "${RED}❌ ECR Repository${NC}: Not found"
fi

# Check S3 Buckets
S3_UPLOADS=$(aws s3 ls | grep -c "shelfshack-dev-uploads" || echo "0")
S3_STATE=$(aws s3 ls | grep -c "shelfshack-terraform-state" || echo "0")
if [ "$S3_UPLOADS" -gt 0 ]; then
    echo -e "${GREEN}✅ S3 Upload Bucket${NC}: shelfshack-dev-uploads exists"
else
    echo -e "${YELLOW}⚠️  S3 Upload Bucket${NC}: shelfshack-dev-uploads (manual - may not exist)"
fi
if [ "$S3_STATE" -gt 0 ]; then
    echo -e "${GREEN}✅ S3 State Bucket${NC}: shelfshack-terraform-state exists"
else
    echo -e "${YELLOW}⚠️  S3 State Bucket${NC}: shelfshack-terraform-state (manual - may not exist)"
fi

echo ""
echo -e "${BLUE}🔐 IAM Resources${NC}"

# Check IAM Roles
check_resource "Deploy Role" \
    "aws iam get-role --role-name shelfshackDeployRole --query 'Role.RoleName' --output text" \
    "RoleName"

check_resource "Execution Role" \
    "aws iam get-role --role-name shelfshack-dev-execution-role --query 'Role.RoleName' --output text" \
    "RoleName"

check_resource "Task Role" \
    "aws iam get-role --role-name shelfshack-dev-task-role --query 'Role.RoleName' --output text" \
    "RoleName"

echo ""
echo -e "${BLUE}📝 CloudWatch Resources${NC}"

# Check Log Groups
LOG_GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "/ecs/shelfshack-dev" --query 'length(logGroups)' --output text 2>/dev/null || echo "0")
if [ "$LOG_GROUPS" -gt 0 ]; then
    echo -e "${GREEN}✅ ECS Log Groups${NC}: $LOG_GROUPS found"
else
    echo -e "${RED}❌ ECS Log Groups${NC}: Not found"
fi

echo ""
echo -e "${GREEN}✅ Verification complete!${NC}"
echo ""
echo -e "${BLUE}💡 Tip: Use 'terraform output' to see all resource endpoints and IDs${NC}"

