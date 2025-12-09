data "aws_region" "current" {}

locals {
  tags = merge(var.tags, {
    Module = "opensearch-container"
  })
}

# CloudWatch Log Group for OpenSearch container
resource "aws_cloudwatch_log_group" "opensearch" {
  name              = "/ecs/${var.name}-opensearch"
  retention_in_days = var.log_retention_in_days
  tags = merge(local.tags, {
    Name = "/ecs/${var.name}-opensearch"
  })
}

# IAM role for ECS task execution (required for Fargate)
data "aws_iam_policy_document" "opensearch_execution_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "opensearch_execution" {
  name               = "${var.name}-opensearch-execution-role"
  assume_role_policy = data.aws_iam_policy_document.opensearch_execution_assume_role.json
  tags = merge(local.tags, {
    Name = "${var.name}-opensearch-execution-role"
  })
}

resource "aws_iam_role_policy_attachment" "opensearch_execution" {
  role       = aws_iam_role.opensearch_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Definition for OpenSearch container
resource "aws_ecs_task_definition" "opensearch" {
  family                   = "${var.name}-opensearch-task"
  cpu                      = var.cpu
  memory                   = var.memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.opensearch_execution.arn
  container_definitions = jsonencode([
    {
      name      = "opensearch"
      image     = var.container_image
      essential = true
      portMappings = [
        {
          containerPort = 9200
          hostPort      = 9200
          protocol      = "tcp"
        },
        {
          containerPort = 9600
          hostPort      = 9600
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "discovery.type"
          value = "single-node"
        },
        {
          name  = "plugins.security.disabled"
          value = "true"
        },
        {
          name  = "bootstrap.memory_lock"
          value = "true"
        },
        {
          name  = "OPENSEARCH_JAVA_OPTS"
          value = var.java_opts
        }
      ]
      ulimits = [
        {
          name      = "memlock"
          softLimit = -1
          hardLimit = -1
        },
        {
          name      = "nofile"
          softLimit = 65536
          hardLimit = 65536
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.opensearch.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "opensearch"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:9200/_cluster/health || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 5
        startPeriod = 60
      }
    }
  ])

  tags = merge(local.tags, {
    Name = "${var.name}-opensearch-task"
  })
}

# Security Group for OpenSearch container
resource "aws_security_group" "opensearch" {
  name        = "${var.name}-opensearch-container-sg"
  description = "Security group for OpenSearch container - allows HTTP from application"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from application security group"
    from_port       = 9200
    to_port         = 9200
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  # Performance analyzer port
  ingress {
    description     = "Performance analyzer from application security group"
    from_port       = 9600
    to_port         = 9600
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
    Name = "${var.name}-opensearch-container-sg"
  })
}

# Service Discovery Namespace (if not provided, service discovery is disabled)
data "aws_service_discovery_dns_namespace" "existing" {
  count = var.service_discovery_namespace_id != null ? 1 : 0
  id    = var.service_discovery_namespace_id
}

# Service Discovery Service (optional)
resource "aws_service_discovery_service" "opensearch" {
  count = var.service_discovery_namespace_id != null ? 1 : 0
  name  = "opensearch"

  dns_config {
    namespace_id = var.service_discovery_namespace_id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_grace_period_seconds = 30

  tags = merge(local.tags, {
    Name = "${var.name}-opensearch-sd"
  })
}

# ECS Service for OpenSearch container
resource "aws_ecs_service" "opensearch" {
  name            = "${var.name}-opensearch-service"
  cluster         = var.ecs_cluster_name
  task_definition = aws_ecs_task_definition.opensearch.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    assign_public_ip = false  # Deploy in private subnets
    security_groups  = [aws_security_group.opensearch.id]
  }

  # Service discovery configuration (optional)
  dynamic "service_registries" {
    for_each = var.service_discovery_namespace_id != null ? [1] : []
    content {
      registry_arn = aws_service_discovery_service.opensearch[0].arn
    }
  }

  # Register with NLB target group (optional)
  dynamic "load_balancer" {
    for_each = var.target_group_arn != null ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = "opensearch"
      container_port   = 9200
    }
  }

  tags = merge(local.tags, {
    Name = "${var.name}-opensearch-service"
  })
}

