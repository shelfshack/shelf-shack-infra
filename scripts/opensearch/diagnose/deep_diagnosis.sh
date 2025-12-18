#!/bin/bash
set -e

echo "=== DEEP DIAGNOSIS: OpenSearch Connection Issue ==="
echo ""

INSTANCE_ID=$(terraform output -raw opensearch_ec2_instance_id 2>/dev/null)
OPENSEARCH_IP=$(terraform output -raw opensearch_ec2_host 2>/dev/null)
OPENSEARCH_SG=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text 2>/dev/null)

echo "1. SECURITY GROUP RULES (Detailed)"
echo "   OpenSearch SG: $OPENSEARCH_SG"
echo ""
echo "   Ingress rules:"
aws ec2 describe-security-groups --group-ids "$OPENSEARCH_SG" \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`9200` || FromPort==`9600`]' \
  --output json 2>/dev/null | jq -r '.[] | "      Port: \(.FromPort)-\(.ToPort) Protocol: \(.IpProtocol) Source: \(.UserIdGroupPairs[0].GroupId // .IpRanges[0].CidrIp // "unknown")"'

echo ""
echo "2. ECS SECURITY GROUP"
CLUSTER=$(terraform output -raw cluster_name 2>/dev/null)
SERVICE=$(terraform output -raw service_name 2>/dev/null)
TASK_DEF=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --query 'services[0].taskDefinition' --output text 2>/dev/null)
ECS_SG=$(aws ecs describe-task-definition --task-definition "$TASK_DEF" --query 'taskDefinition.networkConfiguration.awsvpcConfiguration.securityGroups[0]' --output text 2>/dev/null 2>&1 || echo "N/A")
echo "   ECS Security Group: $ECS_SG"

echo ""
echo "3. CHECKING OPENSEARCH CONTAINER STATUS (via SSM)"
echo "   Attempting to check container status..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["echo \"=== DOCKER STATUS ===\"; sudo docker ps -a | grep opensearch || echo \"No opensearch container\"; echo \"\n=== PORT LISTENING ===\"; sudo netstat -tlnp | grep 9200 || echo \"Port 9200 not listening\"; echo \"\n=== DOCKER LOGS (last 20 lines) ===\"; sudo docker logs opensearch --tail 20 2>&1 || echo \"Cannot get logs\"; echo \"\n=== USER DATA LOG ===\"; sudo tail -30 /var/log/user-data.log 2>&1 || echo \"No user data log\""]' \
  --output-s3-bucket-name "shelfshack-dev-logs" \
  --output-s3-key-prefix "ssm-commands" \
  --query 'Command.CommandId' \
  --output text 2>/dev/null)

if [ -n "$COMMAND_ID" ] && [ "$COMMAND_ID" != "None" ]; then
  echo "   Command ID: $COMMAND_ID"
  echo "   Waiting 5 seconds for command to complete..."
  sleep 5
  echo ""
  echo "   Command Output:"
  aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --query '[StandardOutputContent, StandardErrorContent]' \
    --output text 2>/dev/null || echo "   Error retrieving command output"
else
  echo "   ⚠️  Could not send SSM command (SSM agent may not be ready or instance not accessible)"
fi

echo ""
echo "4. TERRAFORM CONFIGURATION CHECK"
echo "   Checking opensearch_security_disabled setting..."
grep -A 5 "opensearch_security_disabled" terraform.tfvars 2>/dev/null || echo "   Not found in tfvars"

echo ""
echo "5. ECS ENVIRONMENT VARIABLES"
echo "   Checking if OPENSEARCH_USERNAME and OPENSEARCH_PASSWORD are set..."
aws ecs describe-task-definition --task-definition "$TASK_DEF" \
  --query 'taskDefinition.containerDefinitions[0].environment[?name==`OPENSEARCH_USERNAME` || name==`OPENSEARCH_PASSWORD`]' \
  --output table 2>/dev/null || echo "   Not set or error"

