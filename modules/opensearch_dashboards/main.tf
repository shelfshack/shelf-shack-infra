data "aws_region" "current" {}

locals {
  tags = merge(var.tags, {
    Module = "opensearch-dashboards"
  })
}

# CloudWatch Log Group for OpenSearch Dashboards
resource "aws_cloudwatch_log_group" "dashboards" {
  name              = "/ecs/${var.name}-opensearch-dashboards"
  retention_in_days = var.log_retention_in_days
  tags = merge(local.tags, {
    Name = "/ecs/${var.name}-opensearch-dashboards"
  })
}

# IAM role for ECS task execution
data "aws_iam_policy_document" "dashboards_execution_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dashboards_execution" {
  name               = "${var.name}-opensearch-dashboards-execution-role"
  assume_role_policy = data.aws_iam_policy_document.dashboards_execution_assume_role.json
  tags = merge(local.tags, {
    Name = "${var.name}-opensearch-dashboards-execution-role"
  })
}

resource "aws_iam_role_policy_attachment" "dashboards_execution" {
  role       = aws_iam_role.dashboards_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Definition for OpenSearch Dashboards
resource "aws_ecs_task_definition" "dashboards" {
  family                   = "${var.name}-opensearch-dashboards-task"
  cpu                      = var.cpu
  memory                   = var.memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.dashboards_execution.arn
  
  container_definitions = jsonencode([
    {
      name      = "opensearch-dashboards"
      image     = var.container_image
      essential = true
      portMappings = [
        {
          containerPort = 5601
          hostPort      = 5601
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "OPENSEARCH_HOSTS"
          value = jsonencode([var.opensearch_endpoint])
        },
        {
          name  = "DISABLE_SECURITY_DASHBOARDS_PLUGIN"
          value = "true"
        },
        {
          name  = "SERVER_HOST"
          value = "0.0.0.0"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.dashboards.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "dashboards"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:5601/api/status || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 5
        startPeriod = 60
      }
    }
  ])

  tags = merge(local.tags, {
    Name = "${var.name}-opensearch-dashboards-task"
  })
}

# Security Group for OpenSearch Dashboards
resource "aws_security_group" "dashboards" {
  name        = "${var.name}-opensearch-dashboards-sg"
  description = "Security group for OpenSearch Dashboards - allows HTTP/HTTPS from ALB"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from ALB security group"
    from_port       = 5601
    to_port         = 5601
    protocol        = "tcp"
    security_groups = var.alb_security_group_ids
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-opensearch-dashboards-sg"
  })
}

# ECS Service for OpenSearch Dashboards
resource "aws_ecs_service" "dashboards" {
  name            = "${var.name}-opensearch-dashboards-service"
  cluster         = var.ecs_cluster_name
  task_definition = aws_ecs_task_definition.dashboards.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    assign_public_ip = false  # Deploy in private subnets
    security_groups  = [aws_security_group.dashboards.id]
  }

  # Register with load balancer if provided
  dynamic "load_balancer" {
    for_each = var.target_group_arn != null ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = "opensearch-dashboards"
      container_port   = 5601
    }
  }

  tags = merge(local.tags, {
    Name = "${var.name}-opensearch-dashboards-service"
  })
}


