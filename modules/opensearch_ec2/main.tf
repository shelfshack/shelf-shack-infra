locals {
  tags = merge(var.tags, { Module = "opensearch-ec2" })
}

# Get latest Amazon Linux 2023 AMI
data "aws_ssm_parameter" "amazon_linux" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Security group for OpenSearch EC2 instance
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
# Update system
sudo yum update -y

# Install Docker
sudo yum install docker -y

# Start Docker service
sudo service docker start
sudo systemctl enable docker

# Add ec2-user to docker group (optional, for easier management)
sudo usermod -a -G docker ec2-user

# Wait for Docker to be ready
sleep 10

# Run OpenSearch container
sudo docker run -d \
  --name opensearch \
  --restart unless-stopped \
  -p 9200:9200 \
  -p 9600:9600 \
  -e "discovery.type=single-node" \
  -e "OPENSEARCH_JAVA_OPTS=-Xms${var.java_heap_size} -Xmx${var.java_heap_size}" \
  -e "plugins.security.disabled=true" \
  -v opensearch-data:/usr/share/opensearch/data \
  ${var.opensearch_image}:${var.opensearch_version}

# Wait for OpenSearch to start
sleep 30

# Health check
for i in {1..30}; do
  if curl -f http://localhost:9200/_cluster/health; then
    echo "OpenSearch is healthy"
    break
  fi
  echo "Waiting for OpenSearch to be ready... ($i/30)"
  sleep 10
done
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

