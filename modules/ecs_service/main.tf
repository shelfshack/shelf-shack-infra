data "aws_region" "current" {}

locals {
  tags = merge(var.tags, {
    Module = "ecs-service"
  })

  secret_arns = [
    for secret in var.secrets :
    regex("^arn:aws:secretsmanager:[^:]+:[^:]+:secret:[^:]+", secret.value_from)
  ]

  use_alb = var.enable_load_balancer

  service_subnet_ids = length(var.service_subnet_ids) > 0 ? var.service_subnet_ids : (
    var.enable_load_balancer ? var.private_subnet_ids : var.public_subnet_ids
  )

  assign_public_ip = var.enable_load_balancer ? var.assign_public_ip : true

  base_container = {
    name      = var.name
    image     = var.container_image
    essential = true
    portMappings = [
      {
        containerPort = var.container_port
        hostPort      = var.container_port
        protocol      = "tcp"
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = var.name
      }
    }
    environment = concat(
      [
        for env in var.environment_variables : {
          name  = env.name
          value = env.value
        }
      ],
      # Add deployment timestamp when force_new_deployment is enabled
      # This creates a new task definition revision on each apply
      var.force_new_deployment ? [{
        name  = "TF_DEPLOYMENT_TIMESTAMP"
        value = timestamp()
      }] : []
    )
    secrets = [
      for secret in var.secrets : {
        name      = secret.name
        valueFrom = secret.value_from
      }
    ]
  }

  container_definitions = [
    merge(
      local.base_container,
      var.command == null ? {} : { command = var.command }
    )
  ]
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_in_days
  tags = merge(local.tags, {
    Name = "/ecs/${var.name}"
  })
}

resource "aws_cloudwatch_log_group" "exec_logging" {
  name              = "/aws/ecs/executioncommand/${var.name}-cluster"
  retention_in_days = var.log_retention_in_days

  tags = merge(local.tags, {
    Name = "/aws/ecs/executioncommand/${var.name}-cluster"
  })
}

data "aws_iam_policy_document" "ecs_task_execution_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${var.name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume_role.json
  tags = merge(local.tags, {
    Name = "${var.name}-execution-role"
  })
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_secrets" {
  count = length(local.secret_arns) > 0 ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = local.secret_arns
  }
}

resource "aws_iam_policy" "execution_secrets" {
  count  = length(local.secret_arns) > 0 ? 1 : 0
  name   = "${var.name}-execution-secrets"
  policy = data.aws_iam_policy_document.execution_secrets[0].json
}

resource "aws_iam_role_policy_attachment" "task_execution_secrets" {
  count      = length(local.secret_arns) > 0 ? 1 : 0
  role       = aws_iam_role.task_execution.name
  policy_arn = aws_iam_policy.execution_secrets[0].arn
}

resource "aws_iam_role" "task" {
  name               = "${var.name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume_role.json
  tags = merge(local.tags, {
    Name = "${var.name}-task-role"
  })
}

resource "aws_iam_role_policy_attachment" "task_managed" {
  for_each   = toset(var.task_role_managed_policies)
  role       = aws_iam_role.task.name
  policy_arn = each.value
}

# OpenSearch access policy for task role (if enabled)
data "aws_iam_policy_document" "task_opensearch" {
  count = var.enable_opensearch_access ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "es:ESHttpGet",
      "es:ESHttpPost",
      "es:ESHttpPut",
      "es:ESHttpDelete"
    ]
    resources = ["${var.opensearch_domain_arn}/*"]
  }

  statement {
    effect = "Deny"
    actions = ["es:*"]
    not_resources = ["${var.opensearch_domain_arn}/*"]
  }
}

resource "aws_iam_role_policy" "task_opensearch" {
  count  = var.enable_opensearch_access ? 1 : 0
  name   = "${var.name}-task-opensearch-access"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_opensearch[0].json
}

resource "aws_security_group" "alb" {
  count       = local.use_alb ? 1 : 0
  name        = "${var.name}-alb-sg"
  description = "Load balancer security group"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = var.listener_port
    to_port     = var.listener_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-alb-sg"
  })
}

resource "aws_security_group" "service" {
  name        = "${var.name}-svc-sg"
  description = local.use_alb ? "Allow ALB -> ECS tasks" : "Allow public ingress for ECS tasks"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = local.use_alb ? [aws_security_group.alb[0].id] : []
    content {
      from_port       = var.container_port
      to_port         = var.container_port
      protocol        = "tcp"
      security_groups = [ingress.value]
      description     = "Traffic from ALB"
    }
  }

  dynamic "ingress" {
    for_each = local.use_alb ? [] : ["0.0.0.0/0"]
    content {
      from_port   = var.container_port
      to_port     = var.container_port
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "Public ingress"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-svc-sg"
  })
}

resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"

      log_configuration {
        cloud_watch_log_group_name = aws_cloudwatch_log_group.exec_logging.name
      }
    }
  }

  tags = merge(local.tags, {
    Name = "${var.name}-cluster"
  })
}

resource "aws_lb" "this" {
  count              = local.use_alb ? 1 : 0
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[0].id]
  subnets            = var.public_subnet_ids

  tags = merge(local.tags, {
    Name = "${var.name}-alb"
  })
}

resource "aws_lb_target_group" "this" {
  count       = local.use_alb ? 1 : 0
  name        = "${var.name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    interval            = 30
    path                = var.health_check_path
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }

  tags = merge(local.tags, {
    Name = "${var.name}-tg"
  })
}

resource "aws_lb_listener" "http" {
  count             = local.use_alb && !var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.this[0].arn
  port              = var.listener_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  count             = local.use_alb && var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.this[0].arn
  port              = var.listener_port
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  count             = local.use_alb && var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.this[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }

  lifecycle {
    precondition {
      condition     = var.certificate_arn != null
      error_message = "certificate_arn must be set when enable_https is true."
    }
  }
}

resource "aws_route53_record" "alb_alias" {
  count   = local.use_alb && var.route53_zone_id != null && var.route53_record_name != null ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.route53_record_name
  type    = "A"

  alias {
    name                   = aws_lb.this[0].dns_name
    zone_id                = aws_lb.this[0].zone_id
    evaluate_target_health = true
  }
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name}-task"
  cpu                      = var.cpu
  memory                   = var.memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions    = jsonencode(local.container_definitions)

  dynamic "runtime_platform" {
    for_each = [true]
    content {
      operating_system_family = "LINUX"
      cpu_architecture        = "X86_64"
    }
  }

  tags = merge(local.tags, {
    Name = "${var.name}-task"
  })
}

resource "aws_ecs_service" "this" {
  name            = "${var.name}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  force_new_deployment = var.force_new_deployment

  deployment_maximum_percent         = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent

  enable_execute_command = var.enable_execute_command

  network_configuration {
    subnets          = local.service_subnet_ids
    assign_public_ip = local.assign_public_ip
    security_groups = concat(
      [aws_security_group.service.id],
      var.additional_service_security_group_ids
    )
  }

  dynamic "load_balancer" {
    for_each = local.use_alb ? [aws_lb_target_group.this[0].arn] : []
    content {
      target_group_arn = load_balancer.value
      container_name   = var.name
      container_port   = var.container_port
    }
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-service"
  })
}
