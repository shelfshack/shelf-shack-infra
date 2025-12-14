#!/bin/bash
# Access OpenSearch EC2 via bastion host

BASTION_ID=$(terraform output -raw bastion_instance_id 2>/dev/null)
OPENSEARCH_IP=$(terraform output -raw opensearch_ec2_host 2>/dev/null)

if [ -z "$BASTION_ID" ]; then
  echo "Error: Bastion host not found or not enabled"
  exit 1
fi

echo "=== Accessing OpenSearch EC2 via Bastion ==="
echo "Bastion ID: $BASTION_ID"
echo "OpenSearch IP: $OPENSEARCH_IP"
echo ""
echo "This will:"
echo "1. Connect to bastion via SSM"
echo "2. From bastion, SSH to OpenSearch EC2"
echo ""
echo "Note: You'll need to run commands manually once connected."
echo ""

# Connect to bastion
aws ssm start-session --target "$BASTION_ID"
