locals {
  tags = merge(var.tags, { Module = "opensearch-ec2" })
}

# Get latest Amazon Linux 2023 AMI
data "aws_ssm_parameter" "amazon_linux" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Security group for OpenSearch EC2 instance
# Note: Ingress rules are created separately in the calling module to avoid circular dependencies
resource "aws_security_group" "opensearch" {
  name        = "${var.name}-opensearch-ec2-sg"
  description = "Security group for OpenSearch EC2 instance"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(local.tags, {
    Name = "${var.name}-opensearch-ec2-sg"
  })
}

# IAM role for EC2 instance (for CloudWatch logs, SSM access, etc.)
resource "aws_iam_role" "opensearch" {
  name = "${var.name}-opensearch-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = merge(local.tags, {
    Name = "${var.name}-opensearch-ec2-role"
  })
}

# Attach SSM policy for remote access
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.opensearch.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch agent policy (optional, for monitoring)
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  count      = var.enable_cloudwatch_logs ? 1 : 0
  role       = aws_iam_role.opensearch.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Instance profile
resource "aws_iam_instance_profile" "opensearch" {
  name = "${var.name}-opensearch-ec2-profile"
  role = aws_iam_role.opensearch.name

  tags = merge(local.tags, {
    Name = "${var.name}-opensearch-ec2-profile"
  })
}

# User data script to install Docker and run OpenSearch
locals {
  user_data = <<-EOF
#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "=== OPENSEARCH EC2 USER DATA START ==="
echo "Timestamp: $(date)"

# Update system
echo "Updating system packages..."
sudo yum update -y

# Install Docker (curl is already available as curl-minimal in Amazon Linux 2023)
echo "Installing Docker..."
sudo yum install -y docker

# Start Docker service
echo "Starting Docker service..."
sudo systemctl start docker
sudo systemctl enable docker

# Add ec2-user to docker group
sudo usermod -a -G docker ec2-user

# Wait for Docker to be ready
echo "Waiting for Docker to be ready..."
for i in {1..10}; do
  if sudo docker info > /dev/null 2>&1; then
    echo "Docker is ready"
    break
  fi
  echo "Waiting for Docker... ($i/10)"
  sleep 2
done

# Remove existing container if it exists (for updates)
echo "Checking for existing OpenSearch container..."
if sudo docker ps -a --format '{{.Names}}' | grep -q '^opensearch$'; then
  echo "Removing existing OpenSearch container..."
  sudo docker stop opensearch || true
  sudo docker rm opensearch || true
fi

# Run OpenSearch container
echo "Starting OpenSearch container..."
echo "Security disabled: ${var.opensearch_security_disabled}"
%{ if !var.opensearch_security_disabled ~}
# Security enabled - use password authentication
echo "Configuring OpenSearch with security enabled (password: ${var.opensearch_admin_username})"
sudo docker run -d \
  --name opensearch \
  --restart unless-stopped \
  --memory="4g" \
  --memory-swap="4g" \
  -p 9200:9200 \
  -p 9600:9600 \
  -e "discovery.type=single-node" \
  -e "network.host=0.0.0.0" \
  -e "OPENSEARCH_JAVA_OPTS=-Xms${var.java_heap_size} -Xmx${var.java_heap_size}" \
  -e "plugins.security.disabled=false" \
  -e "plugins.security.ssl.http.enabled=false" \
  -e "plugins.security.ssl.transport.enabled=false" \
  -e "plugins.security.authcz.admin_dn=CN=admin" \
  -e "OPENSEARCH_INITIAL_ADMIN_PASSWORD=${var.opensearch_admin_password}" \
  -e "DISABLE_INSTALL_DEMO_CONFIG=true" \
  -v opensearch-data:/usr/share/opensearch/data \
  ${var.opensearch_image}:${var.opensearch_version}
%{ else ~}
# Security disabled - no authentication
# Note: For OpenSearch 2.12.0+, we still need to provide a password to prevent auto-enable
# but we disable the security plugin so no authentication is required
echo "Configuring OpenSearch with security DISABLED (no password required)"
sudo docker run -d \
  --name opensearch \
  --restart unless-stopped \
  --memory="4g" \
  --memory-swap="4g" \
  -p 9200:9200 \
  -p 9600:9600 \
  -e "discovery.type=single-node" \
  -e "network.host=0.0.0.0" \
  -e "OPENSEARCH_JAVA_OPTS=-Xms${var.java_heap_size} -Xmx${var.java_heap_size}" \
  -e "plugins.security.disabled=true" \
  -e "OPENSEARCH_INITIAL_ADMIN_PASSWORD=${var.opensearch_admin_password}" \
  -e "DISABLE_INSTALL_DEMO_CONFIG=true" \
  -v opensearch-data:/usr/share/opensearch/data \
  ${var.opensearch_image}:${var.opensearch_version}
%{ endif ~}

# Verify container started (with timeout to avoid hanging)
echo "Verifying container started..."
sleep 5
CONTAINER_RUNNING=false
for i in {1..6}; do
  if sudo docker ps --format '{{.Names}}' | grep -q '^opensearch$'; then
    CONTAINER_RUNNING=true
    echo "Container is running"
    break
  fi
  echo "Waiting for container... ($i/6)"
  sleep 5
done

if [ "$CONTAINER_RUNNING" = "false" ]; then
  echo "WARNING: Container not found in running containers"
  echo "Checking all containers (including stopped):"
  sudo docker ps -a | grep opensearch || echo "No opensearch container found"
  echo ""
  echo "Container exit code:"
  EXIT_CODE=$(sudo docker inspect opensearch --format='{{.State.ExitCode}}' 2>/dev/null || echo "N/A")
  echo "Exit code: $EXIT_CODE"
  echo ""
  echo "Checking for OOM kill:"
  OOM_KILLED=$(sudo docker inspect opensearch --format='{{.State.OOMKilled}}' 2>/dev/null || echo "N/A")
  echo "OOM Killed: $OOM_KILLED"
  if [ "$OOM_KILLED" = "true" ]; then
    echo "ERROR: Container was killed due to Out of Memory!"
    echo "System memory info:"
    free -h || echo "free command not available"
    echo ""
    echo "Consider:"
    echo "1. Using a larger instance type (t3.small with 2GB RAM)"
    echo "2. Further reducing heap size (current: ${var.java_heap_size})"
  fi
  echo ""
  echo "Container logs (if exists):"
  sudo docker logs opensearch --tail 50 2>&1 || echo "Cannot get logs"
  echo ""
  echo "System memory usage:"
  free -h 2>/dev/null || echo "free command not available"
  echo ""
  # Don't exit - try to continue
fi

# Wait for OpenSearch to initialize (with memory check)
echo "Waiting for OpenSearch to initialize..."
echo "System memory before wait:"
free -h 2>/dev/null || echo "free command not available"
sleep 20
echo "System memory after wait:"
free -h 2>/dev/null || echo "free command not available"

# Check if container is running
echo "=== Container Status ==="
CONTAINER_STATUS=$(sudo docker ps -a --filter name=opensearch --format '{{.Status}}' || echo "NOT FOUND")
echo "Container status: $CONTAINER_STATUS"
sudo docker ps -a | grep opensearch || echo "WARNING: OpenSearch container not found"

# Check container logs for errors
echo "=== Container Logs (last 30 lines) ==="
sudo docker logs opensearch --tail 30 2>&1 || echo "Could not retrieve container logs"

# Verify port is listening
echo "=== Port 9200 Status ==="
if sudo netstat -tlnp 2>/dev/null | grep -q ':9200 ' || sudo ss -tlnp 2>/dev/null | grep -q ':9200 '; then
  echo "Port 9200 is listening"
  sudo netstat -tlnp 2>/dev/null | grep ':9200 ' || sudo ss -tlnp 2>/dev/null | grep ':9200 '
else
  echo "WARNING: Port 9200 is NOT listening"
fi

# Health check (with auth if security is enabled)
OPENSEARCH_USER="${var.opensearch_admin_username}"
OPENSEARCH_PASS="${var.opensearch_admin_password}"
%{ if !var.opensearch_security_disabled ~}
echo "Testing OpenSearch health with authentication..."
for i in {1..30}; do
  if curl -u "$OPENSEARCH_USER:$OPENSEARCH_PASS" -f http://localhost:9200/_cluster/health; then
    echo "OpenSearch is healthy"
    # Also test from external interface
    PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
    echo "Testing connection from external IP: $PRIVATE_IP"
    curl -u "$OPENSEARCH_USER:$OPENSEARCH_PASS" -f http://$PRIVATE_IP:9200/_cluster/health && echo "External connection successful" || echo "External connection failed"
    break
  fi
  echo "Waiting for OpenSearch to be ready... ($i/30)"
  sleep 10
done
%{ else ~}
echo "Testing OpenSearch health without authentication..."
for i in {1..30}; do
  if curl -f http://localhost:9200/_cluster/health; then
    echo "OpenSearch is healthy"
    # Also test from external interface
    PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
    echo "Testing connection from external IP: $PRIVATE_IP"
    curl -f http://$PRIVATE_IP:9200/_cluster/health && echo "External connection successful" || echo "External connection failed"
    break
  fi
  echo "Waiting for OpenSearch to be ready... ($i/30)"
  sleep 10
done
%{ endif ~}
EOF
}

# EC2 instance for OpenSearch
resource "aws_instance" "opensearch" {
  ami                         = data.aws_ssm_parameter.amazon_linux.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.opensearch.name
  vpc_security_group_ids      = [aws_security_group.opensearch.id]
  user_data                   = local.user_data

  # Root volume configuration
  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }

  tags = merge(local.tags, {
    Name = "${var.name}-opensearch-ec2"
  })
}

