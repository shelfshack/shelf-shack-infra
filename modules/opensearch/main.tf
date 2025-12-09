data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  tags = merge(var.tags, {
    Module = "opensearch"
  })
  
  # Construct OpenSearch domain ARN manually to avoid circular dependency
  opensearch_domain_arn = "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${var.domain_name}"
}

# Security group for OpenSearch domain
resource "aws_security_group" "opensearch" {
  name        = "${var.name}-opensearch-sg"
  description = "Security group for OpenSearch domain - allows HTTPS from application"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTPS from application security group"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  # Optional: Allow HTTPS from specific IP addresses (for Kibana/Dashboards access)
  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []
    content {
      description = "HTTPS from allowed CIDR blocks (e.g., for Kibana access)"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-opensearch-sg"
  })
}

# IAM access policy for OpenSearch domain
data "aws_iam_policy_document" "opensearch_access" {
  # Allow full access from the application IAM role
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = var.iam_role_arns
    }
    actions   = ["es:*"]
    resources = ["${local.opensearch_domain_arn}/*"]
  }

  # Optional: Allow access from specific IP addresses (for Kibana/Dashboards)
  dynamic "statement" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []
    content {
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = ["*"]
      }
      actions   = ["es:*"]
      resources = ["${local.opensearch_domain_arn}/*"]
      condition {
        test     = "IpAddress"
        variable = "aws:SourceIp"
        values   = var.allowed_cidr_blocks
      }
    }
  }
}

# OpenSearch Service Domain
resource "aws_opensearch_domain" "this" {
  domain_name    = var.domain_name
  engine_version = var.engine_version

  cluster_config {
    instance_type            = var.instance_type
    instance_count           = var.instance_count
    dedicated_master_enabled = false
    zone_awareness_enabled   = var.instance_count > 1
    dynamic "zone_awareness_config" {
      for_each = var.instance_count > 1 ? [1] : []
      content {
        availability_zone_count = min(var.instance_count, length(var.subnet_ids))
      }
    }
  }

  # VPC configuration - deploy in private subnets
  vpc_options {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.opensearch.id]
  }

  # Encryption at rest
  encrypt_at_rest {
    enabled = true
  }

  # Node-to-node encryption
  node_to_node_encryption {
    enabled = true
  }

  # Enforce HTTPS
  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  # Fine-grained access control with IAM
  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = false
    master_user_options {
      master_user_arn = var.master_user_arn != null ? var.master_user_arn : null
    }
  }

  # Access policy
  access_policies = data.aws_iam_policy_document.opensearch_access.json

  # EBS volume configuration
  ebs_options {
    ebs_enabled = true
    volume_size = var.ebs_volume_size
    volume_type = var.ebs_volume_type
  }

  # Log publishing (optional)
  dynamic "log_publishing_options" {
    for_each = var.enable_cloudwatch_logs ? ["INDEX_SLOW_LOGS", "SEARCH_SLOW_LOGS"] : []
    content {
      log_type                 = log_publishing_options.value
      cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch[log_publishing_options.value].arn
    }
  }

  # Note: Automated snapshots are managed automatically by AWS OpenSearch Service
  # The snapshot start hour is not configurable via Terraform

  tags = merge(local.tags, {
    Name = var.domain_name
  })

  # Only depend on service-linked role if we're creating it
  # If the role already exists in the account (create_service_linked_role = false), no dependency is needed
  # Note: When create_service_linked_role is false, the role resource doesn't exist, so we use an empty list
}

# IAM service-linked role for OpenSearch (required for VPC deployments)
resource "aws_iam_service_linked_role" "opensearch" {
  count            = var.create_service_linked_role ? 1 : 0
  aws_service_name = "opensearchservice.amazonaws.com"
  description      = "Service-linked role for OpenSearch Service"
}

# CloudWatch Log Groups for OpenSearch (optional)
resource "aws_cloudwatch_log_group" "opensearch" {
  for_each = var.enable_cloudwatch_logs ? toset(["INDEX_SLOW_LOGS", "SEARCH_SLOW_LOGS"]) : toset([])

  name              = "/aws/opensearch/domains/${var.domain_name}/${each.value}"
  retention_in_days = var.log_retention_in_days

  tags = merge(local.tags, {
    Name = "/aws/opensearch/domains/${var.domain_name}/${each.value}"
  })
}

# CloudWatch Log Resource Policy (required for OpenSearch to write logs)
resource "aws_cloudwatch_log_resource_policy" "opensearch" {
  count           = var.enable_cloudwatch_logs ? 1 : 0
  policy_name     = "${var.domain_name}-opensearch-logs"
  policy_document = data.aws_iam_policy_document.opensearch_logs[0].json
}

data "aws_iam_policy_document" "opensearch_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  statement {
    effect = "Allow"
    principals {
      identifiers = ["es.amazonaws.com"]
      type        = "Service"
    }
    actions = [
      "logs:PutLogEvents",
      "logs:CreateLogStream",
    ]
    resources = [
      "${aws_cloudwatch_log_group.opensearch["INDEX_SLOW_LOGS"].arn}:*",
      "${aws_cloudwatch_log_group.opensearch["SEARCH_SLOW_LOGS"].arn}:*"
    ]
  }
}

