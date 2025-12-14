#!/bin/bash
# Comprehensive diagnosis script

echo "=== COMPREHENSIVE OPENSEARCH DIAGNOSIS ==="
echo ""

INSTANCE_ID=$(terraform output -raw opensearch_ec2_instance_id 2>/dev/null)
OPENSEARCH_IP=$(terraform output -raw opensearch_ec2_host 2>/dev/null)
CLUSTER=$(terraform output -raw cluster_name 2>/dev/null)
SERVICE=$(terraform output -raw service_name 2>/dev/null)

echo "1. INFRASTRUCTURE CHECK"
echo "   Instance ID: ${INSTANCE_ID:-NOT FOUND}"
echo "   OpenSearch IP: ${OPENSEARCH_IP:-NOT FOUND}"
echo "   Error shows IP: 10.0.10.229"
echo ""

if [ "$OPENSEARCH_IP" != "10.0.10.229" ] && [ -n "$OPENSEARCH_IP" ]; then
  echo "   ⚠️  IP MISMATCH - ECS has stale IP!"
  echo "   Need to restart ECS service to get new IP"
fi

echo ""
echo "2. SECURITY GROUP VERIFICATION"
if [ -n "$INSTANCE_ID" ]; then
  SG_ID=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text 2>/dev/null)
  echo "   OpenSearch SG: $SG_ID"
  
  echo "   Checking ingress rules for port 9200:"
  aws ec2 describe-security-group-rules \
    --filters "Name=group-id,Values=$SG_ID" "Name=is-egress,Values=false" "Name=from-port,Values=9200" \
    --query 'SecurityGroupRules[*].[FromPort,ToPort,Protocol,SourceSecurityGroupId,Description]' \
    --output table 2>/dev/null || echo "   No rules found or error"
fi

echo ""
echo "3. ECS SERVICE CONFIGURATION"
if [ -n "$CLUSTER" ] && [ -n "$SERVICE" ]; then
  echo "   Getting task definition to check environment variables..."
  TASK_DEF=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --query 'services[0].taskDefinition' --output text 2>/dev/null)
  if [ -n "$TASK_DEF" ] && [ "$TASK_DEF" != "None" ]; then
    echo "   Task Definition: $TASK_DEF"
    echo "   Checking OPENSEARCH_HOST environment variable:"
    aws ecs describe-task-definition --task-definition "$TASK_DEF" --query 'taskDefinition.containerDefinitions[0].environment[?name==`OPENSEARCH_HOST`]' --output table 2>/dev/null
  fi
fi

echo ""
echo "4. INSTANCE STATUS"
if [ -n "$INSTANCE_ID" ]; then
  aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].[State.Name,PrivateIpAddress,LaunchTime]' \
    --output table
fi

