#!/bin/bash
# Fix OpenSearch container on EC2 instance

INSTANCE_ID=$(terraform output -raw opensearch_ec2_instance_id 2>/dev/null)

if [ -z "$INSTANCE_ID" ]; then
  echo "Error: Could not get OpenSearch EC2 instance ID"
  echo "Make sure you're in the envs/dev directory and terraform has been applied"
  exit 1
fi

echo "Fixing OpenSearch container on instance: $INSTANCE_ID"
echo "This will stop the existing container and start a new one with the password..."

aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "echo \"Stopping existing OpenSearch container...\"",
    "sudo docker stop opensearch || true",
    "sudo docker rm opensearch || true",
    "echo \"Starting new OpenSearch container with password...\"",
    "sudo docker run -d --name opensearch --restart unless-stopped -p 9200:9200 -p 9600:9600 -e \"discovery.type=single-node\" -e \"OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m\" -e \"plugins.security.disabled=true\" -e \"OPENSEARCH_INITIAL_ADMIN_PASSWORD=OpenSearch@2024!\" -v opensearch-data:/usr/share/opensearch/data opensearchproject/opensearch:latest",
    "echo \"Waiting for OpenSearch to start (this may take 1-2 minutes)...\"",
    "sleep 60",
    "echo \"Checking OpenSearch health...\"",
    "curl -s http://localhost:9200/_cluster/health || echo \"Still starting, wait a bit longer and check manually\""
  ]' \
  --output text \
  --query 'Command.CommandId'

echo ""
echo "Command sent! Check the status with:"
echo "  aws ssm list-command-invocations --command-id <COMMAND_ID> --details"
echo ""
echo "Or connect to the instance and check manually:"
echo "  aws ssm start-session --target $INSTANCE_ID"
echo "  sudo docker logs opensearch"
echo "  curl http://localhost:9200/_cluster/health"
