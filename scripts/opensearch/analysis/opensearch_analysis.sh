#!/bin/bash
# Comprehensive OpenSearch connectivity analysis

echo "=== OpenSearch Connectivity Analysis ==="
echo ""

# Get infrastructure details
INSTANCE_ID=$(terraform output -raw opensearch_ec2_instance_id 2>/dev/null)
OPENSEARCH_IP=$(terraform output -raw opensearch_ec2_host 2>/dev/null)
SG_ID=$(terraform output -raw opensearch_ec2_security_group_id 2>/dev/null 2>/dev/null || echo "Check manually")
ECS_SG_ID=$(terraform output -raw service_security_group_id 2>/dev/null || echo "Check manually")

echo "1. INFRASTRUCTURE DETAILS"
echo "   OpenSearch EC2 Instance ID: ${INSTANCE_ID:-NOT FOUND}"
echo "   OpenSearch Private IP: ${OPENSEARCH_IP:-NOT FOUND}"
echo "   Expected IP from error: 10.0.10.181"
echo ""

# Check instance status
echo "2. EC2 INSTANCE STATUS"
if [ -n "$INSTANCE_ID" ]; then
  aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].[State.Name,PrivateIpAddress,LaunchTime,SubnetId]' \
    --output table
else
  echo "   Instance ID not found in Terraform outputs"
  echo "   Searching for instance by tag..."
  aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=shelfshack-dev-opensearch-ec2" \
    --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PrivateIpAddress]' \
    --output table
fi
echo ""

# Check security groups
echo "3. SECURITY GROUP CONFIGURATION"
if [ -n "$SG_ID" ] && [ "$SG_ID" != "Check manually" ]; then
  echo "   OpenSearch SG: $SG_ID"
  aws ec2 describe-security-group-rules \
    --filters "Name=group-id,Values=$SG_ID" \
    --query 'SecurityGroupRules[?FromPort==`9200`].[FromPort,ToPort,Protocol,SourceSecurityGroupId,Description]' \
    --output table
else
  echo "   Getting security group from instance..."
  if [ -n "$INSTANCE_ID" ]; then
    INSTANCE_SG=$(aws ec2 describe-instances \
      --instance-ids "$INSTANCE_ID" \
      --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
      --output text 2>/dev/null)
    echo "   Instance Security Group: $INSTANCE_SG"
    if [ -n "$INSTANCE_SG" ]; then
      aws ec2 describe-security-group-rules \
        --filters "Name=group-id,Values=$INSTANCE_SG" \
        --query 'SecurityGroupRules[?FromPort==`9200`]' \
        --output table
    fi
  fi
fi
echo ""

# Check ECS service security group
echo "4. ECS SERVICE SECURITY GROUP"
if [ -n "$ECS_SG_ID" ] && [ "$ECS_SG_ID" != "Check manually" ]; then
  echo "   ECS Service SG: $ECS_SG_ID"
else
  echo "   Getting from ECS service..."
  CLUSTER=$(terraform output -raw cluster_name 2>/dev/null)
  SERVICE=$(terraform output -raw service_name 2>/dev/null)
  if [ -n "$CLUSTER" ] && [ -n "$SERVICE" ]; then
    TASK_ARN=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICE" --query 'taskArns[0]' --output text 2>/dev/null)
    if [ -n "$TASK_ARN" ] && [ "$TASK_ARN" != "None" ]; then
      ENI=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text 2>/dev/null)
      if [ -n "$ENI" ]; then
        ECS_SG=$(aws ec2 describe-network-interfaces --network-interface-ids "$ENI" --query 'NetworkInterfaces[0].Groups[0].GroupId' --output text 2>/dev/null)
        echo "   ECS Service SG: $ECS_SG"
      fi
    fi
  fi
fi
echo ""

# Network connectivity analysis
echo "5. NETWORK CONNECTIVITY ANALYSIS"
echo "   Issue: Connection refused (Errno 111)"
echo "   This means:"
echo "     - Network path exists (no timeout)"
echo "     - Security groups allow traffic"
echo "     - BUT: No service listening on port 9200"
echo "   Root cause: OpenSearch container not running or not listening"
echo ""

# Check if instance was recreated
echo "6. INSTANCE RECREATION CHECK"
if [ "$OPENSEARCH_IP" != "10.0.10.181" ] && [ -n "$OPENSEARCH_IP" ]; then
  echo "   ⚠️  IP MISMATCH!"
  echo "   Terraform output IP: $OPENSEARCH_IP"
  echo "   Error shows IP: 10.0.10.181"
  echo "   This suggests:"
  echo "     - Instance was recreated (new IP)"
  echo "     - ECS service has stale IP in OPENSEARCH_HOST env var"
  echo "     - Need to restart ECS service to get new IP"
fi
echo ""

echo "=== RECOMMENDED ACTIONS ==="
echo ""
echo "1. Verify instance IP matches Terraform output"
echo "2. Check if OpenSearch container is running (via bastion or recreate)"
echo "3. Restart ECS service to refresh OPENSEARCH_HOST env var"
echo "4. Verify security group rules allow ECS → EC2 on port 9200"
