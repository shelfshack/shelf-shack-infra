data "aws_region" "current" {}

locals {
  tags = merge(var.tags, {
    Module = "opensearch-nlb"
  })
}

# Internal Network Load Balancer for OpenSearch
resource "aws_lb" "opensearch" {
  name               = "${var.name}-opensearch-nlb"
  internal           = true  # Internal NLB in private subnets
  load_balancer_type = "network"
  subnets            = var.subnet_ids

  enable_deletion_protection = false

  tags = merge(local.tags, {
    Name = "${var.name}-opensearch-nlb"
  })
}

# Target Group for OpenSearch
resource "aws_lb_target_group" "opensearch" {
  name        = "${var.name}-opensearch-tg"
  port        = 9200
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    protocol            = "TCP"
    port                = 9200
  }

  tags = merge(local.tags, {
    Name = "${var.name}-opensearch-tg"
  })
}

# NLB Listener
resource "aws_lb_listener" "opensearch" {
  load_balancer_arn = aws_lb.opensearch.arn
  port              = "9200"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.opensearch.arn
  }
}

# Security Group for NLB (allows traffic from backend service)
resource "aws_security_group" "nlb" {
  name        = "${var.name}-opensearch-nlb-sg"
  description = "Security group for OpenSearch NLB"
  vpc_id      = var.vpc_id

  ingress {
    description     = "TCP from backend service security group"
    from_port       = 9200
    to_port         = 9200
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-opensearch-nlb-sg"
  })
}

# Note: Security group rule for OpenSearch container is created in main.tf
# to avoid circular dependency

