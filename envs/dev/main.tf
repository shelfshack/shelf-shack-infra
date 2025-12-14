terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data source to fetch DB password from AWS Secrets Manager (optional)
data "aws_secretsmanager_secret_version" "db_password" {
  count     = var.db_master_password_secret_arn != null ? 1 : 0
  secret_id = var.db_master_password_secret_arn
}

locals {
  name = "${var.project}-${var.environment}"
  tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.default_tags
  )

  environment_variables = [
    for key, value in var.app_environment : {
      name  = key
      value = value
    }
  ]

  # Priority: Secrets Manager > var.db_master_password > var.DB_MASTER_PASSWORD
  db_master_password = var.db_master_password_secret_arn != null ? (
    try(jsondecode(data.aws_secretsmanager_secret_version.db_password[0].secret_string)["password"], data.aws_secretsmanager_secret_version.db_password[0].secret_string)
  ) : (
    var.db_master_password != null ? var.db_master_password : var.DB_MASTER_PASSWORD
  )
}

module "networking" {
  source = "../../modules/networking"

  name                 = local.name
  cidr_block           = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
  enable_ssm_endpoints = var.enable_ssm_endpoints
  tags                 = local.tags
}

module "bastion" {
  source = "../../modules/bastion_host"

  enabled               = var.enable_bastion_host
  name                  = local.name
  subnet_id             = module.networking.private_subnet_ids[0]
  vpc_id                = module.networking.vpc_id
  instance_type         = var.bastion_instance_type
  allow_ssh_cidr_blocks = var.bastion_allow_ssh_cidr_blocks
  tags                  = local.tags
}

module "ecr" {
  source = "../../modules/ecr_repository"

  name                 = "${local.name}-repo"
  image_tag_mutability = var.image_tag_mutability
  scan_on_push         = var.scan_ecr_on_push
  tags                 = local.tags
}

module "ecs_service" {
  source = "../../modules/ecs_service"

  name                        = local.name
  vpc_id                      = module.networking.vpc_id
  public_subnet_ids           = module.networking.public_subnet_ids
  private_subnet_ids          = module.networking.private_subnet_ids
  container_image             = "${module.ecr.repository_url}:${var.container_image_tag}"
  container_port              = var.container_port
  cpu                         = var.cpu
  memory                      = var.memory
  desired_count               = var.desired_count
  assign_public_ip            = var.assign_public_ip
  enable_load_balancer        = var.enable_load_balancer
  service_subnet_ids          = var.service_subnet_ids
  environment_variables       = concat(
    local.environment_variables,
    # Add OpenSearch configuration if EC2 OpenSearch is enabled
    var.enable_opensearch_ec2 ? concat([
      {
        name  = "OPENSEARCH_HOST"
        value = module.opensearch_ec2[0].opensearch_host
      },
      {
        name  = "OPENSEARCH_PORT"
        value = "9200"
      },
      {
        name  = "OPENSEARCH_USE_SSL"
        value = "false"
      },
      {
        name  = "OPENSEARCH_VERIFY_CERTS"
        value = "false"
      }
    ],
    # Add authentication if password is provided
    var.opensearch_ec2_admin_password != null ? [
      {
        name  = "OPENSEARCH_USERNAME"
        value = "admin"
      },
      {
        name  = "OPENSEARCH_PASSWORD"
        value = var.opensearch_ec2_admin_password
      }
    ] : []) : []
  )
  secrets                     = var.app_secrets
  health_check_path           = var.health_check_path
  listener_port               = var.listener_port
  enable_https                = var.enable_https
  certificate_arn             = var.certificate_arn
  route53_zone_id             = var.route53_zone_id
  route53_record_name         = var.route53_record_name
  log_retention_in_days       = var.log_retention_in_days
  deployment_maximum_percent  = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  enable_execute_command             = var.enable_execute_command
  force_new_deployment               = var.force_new_deployment
  task_role_managed_policies         = var.task_role_managed_policies
  s3_bucket_name                     = lookup(var.app_environment, "S3_BUCKET_NAME", null)
  additional_service_security_group_ids = var.extra_service_security_group_ids
  command                              = var.command
  # Temporarily disabled AWS OpenSearch Service - using EC2-based version instead
  # opensearch_domain_arn                = module.opensearch.domain_arn
  # enable_opensearch_access             = true
  opensearch_domain_arn                = null
  enable_opensearch_access             = false
  tags                                 = local.tags

  depends_on = [module.rds]
}

module "rds" {
  source = "../../modules/rds_postgres"

  name                       = local.name
  vpc_id                     = module.networking.vpc_id
  subnet_ids                 = module.networking.private_subnet_ids
  db_name                    = var.db_name
  master_username            = var.db_master_username
  master_password            = local.db_master_password
  allocated_storage          = var.db_allocated_storage
  engine_version             = var.db_engine_version
  multi_az                   = var.db_multi_az
  backup_retention_period    = var.db_backup_retention_days
  skip_final_snapshot        = var.db_skip_final_snapshot
  deletion_protection        = var.db_deletion_protection
  apply_immediately          = var.db_apply_immediately
  publicly_accessible        = var.db_publicly_accessible
  tags                       = local.tags
}

resource "aws_security_group_rule" "rds_from_ecs" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.rds.security_group_id
  source_security_group_id = module.ecs_service.service_security_group_id
}

resource "aws_security_group_rule" "rds_from_bastion" {
  count                    = var.enable_bastion_host ? 1 : 0
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.rds.security_group_id
  source_security_group_id = module.bastion.security_group_id
}

# ============================================================================
# OpenSearch on EC2 (Replaces ECS-based OpenSearch)
# ============================================================================
module "opensearch_ec2" {
  count  = var.enable_opensearch_ec2 ? 1 : 0
  source = "../../modules/opensearch_ec2"

  name                        = local.name
  vpc_id                      = module.networking.vpc_id
  subnet_id                   = module.networking.private_subnet_ids[0]
  instance_type               = var.opensearch_ec2_instance_type
  opensearch_image            = var.opensearch_ec2_image
  opensearch_version          = var.opensearch_ec2_version
  java_heap_size              = var.opensearch_ec2_java_heap_size
  opensearch_admin_username   = var.opensearch_ec2_admin_username
  opensearch_admin_password   = var.opensearch_ec2_admin_password
  opensearch_security_disabled = var.opensearch_ec2_security_disabled
  enable_cloudwatch_logs      = false
  tags                        = local.tags
}

# Security group rules for OpenSearch EC2 (created separately to avoid circular dependency)
resource "aws_security_group_rule" "opensearch_from_ecs_http" {
  count                    = var.enable_opensearch_ec2 ? 1 : 0
  type                     = "ingress"
  from_port                = 9200
  to_port                  = 9200
  protocol                 = "tcp"
  security_group_id        = module.opensearch_ec2[0].security_group_id
  source_security_group_id = module.ecs_service.service_security_group_id
  description              = "OpenSearch HTTP from ECS service"
}

resource "aws_security_group_rule" "opensearch_from_ecs_perf" {
  count                    = var.enable_opensearch_ec2 ? 1 : 0
  type                     = "ingress"
  from_port                = 9600
  to_port                  = 9600
  protocol                 = "tcp"
  security_group_id        = module.opensearch_ec2[0].security_group_id
  source_security_group_id = module.ecs_service.service_security_group_id
  description              = "OpenSearch performance analyzer from ECS service"
}

resource "aws_security_group_rule" "opensearch_from_bastion" {
  count                    = var.enable_opensearch_ec2 && var.enable_bastion_host ? 1 : 0
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = module.opensearch_ec2[0].security_group_id
  source_security_group_id = module.bastion.security_group_id
  description              = "SSH from bastion host"
}

# ============================================================================
# AWS OpenSearch Service (TEMPORARILY DISABLED - Using EC2-based version)
# ============================================================================
# 
# COMMENTED OUT: This module provisions an Amazon OpenSearch Service domain.
# We're temporarily using a containerized OpenSearch (opensearchproject/opensearch:2.11.0)
# running as an ECS service instead, as AWS OpenSearch Service requires a paid account.
# 
# To re-enable AWS OpenSearch Service:
# 1. Uncomment the module "opensearch" block below
# 2. Uncomment the opensearch access policy resources
# 3. Update module.ecs_service to enable_opensearch_access = true
# 4. Remove or comment out module.opensearch_container below
#
# module "opensearch" {
#   source = "../../modules/opensearch"
#
#   name                = local.name
#   domain_name         = var.opensearch_domain_name
#   engine_version      = var.opensearch_engine_version
#   instance_type       = var.opensearch_instance_type
#   instance_count      = var.opensearch_instance_count
#   vpc_id              = module.networking.vpc_id
#   subnet_ids          = module.networking.private_subnet_ids
#   allowed_security_group_ids = []
#   allowed_cidr_blocks = var.opensearch_allowed_cidr_blocks
#   iam_role_arns       = var.opensearch_iam_role_arns
#   master_user_arn     = var.opensearch_master_user_arn
#   ebs_volume_size     = var.opensearch_ebs_volume_size
#   ebs_volume_type     = var.opensearch_ebs_volume_type
#   enable_cloudwatch_logs = var.opensearch_enable_cloudwatch_logs
#   log_retention_in_days  = var.opensearch_log_retention_in_days
#   create_service_linked_role = var.opensearch_create_service_linked_role
#   tags                = local.tags
# }
#
# data "aws_iam_policy_document" "opensearch_with_ecs_role" {
#   statement {
#     effect = "Allow"
#     principals {
#       type        = "AWS"
#       identifiers = concat(
#         var.opensearch_iam_role_arns,
#         [module.ecs_service.task_role_arn]
#       )
#     }
#     actions   = ["es:*"]
#     resources = ["${module.opensearch.domain_arn}/*"]
#   }
# }
#
# resource "aws_opensearch_domain_policy" "update_access_policy" {
#   domain_name = module.opensearch.domain_name
#   access_policies = data.aws_iam_policy_document.opensearch_with_ecs_role.json
#   depends_on = [module.opensearch, module.ecs_service]
# }
#
# resource "aws_security_group_rule" "opensearch_from_ecs" {
#   type                     = "ingress"
#   from_port                = 443
#   to_port                  = 443
#   protocol                 = "tcp"
#   security_group_id        = module.opensearch.security_group_id
#   source_security_group_id = module.ecs_service.service_security_group_id
#   description              = "Allow HTTPS from ECS service to OpenSearch"
#   depends_on = [module.opensearch, module.ecs_service]
# }

# ============================================================================
# Containerized OpenSearch Service (DISABLED - Using PostgreSQL for search)
# ============================================================================
#
# OpenSearch has been disabled in AWS to avoid free tier limitations.
# The backend application will automatically fall back to PostgreSQL for search.
# OpenSearch remains available for local development via docker-compose.
#
# To re-enable OpenSearch in AWS:
# 1. Uncomment the modules below
# 2. Set OPENSEARCH_HOST environment variable in ECS service
# 3. Deploy the infrastructure
#
# module "opensearch_nlb" {
#   source = "../../modules/opensearch_nlb"
#
#   name                        = local.name
#   vpc_id                      = module.networking.vpc_id
#   subnet_ids                  = module.networking.private_subnet_ids
#   opensearch_security_group_id = null
#   allowed_security_group_ids  = [module.ecs_service.service_security_group_id]
#   tags                        = local.tags
#
#   depends_on = [module.ecs_service]
# }
#
# module "opensearch_container" {
#   source = "../../modules/opensearch_container"
#
#   name                  = local.name
#   vpc_id                = module.networking.vpc_id
#   subnet_ids            = module.networking.private_subnet_ids
#   ecs_cluster_name      = module.ecs_service.cluster_name
#   allowed_security_group_ids = [module.ecs_service.service_security_group_id]
#   target_group_arn      = module.opensearch_nlb.target_group_arn
#   container_image       = "opensearchproject/opensearch:2.11.0"
#   cpu                   = 512
#   memory                = 1024
#   java_opts             = "-Xms512m -Xmx512m"
#   log_retention_in_days = var.log_retention_in_days
#   tags                  = local.tags
#
#   depends_on = [module.ecs_service, module.opensearch_nlb]
# }
#
# resource "aws_security_group_rule" "opensearch_from_nlb" {
#   type                     = "ingress"
#   from_port                = 9200
#   to_port                  = 9200
#   protocol                 = "tcp"
#   security_group_id        = module.opensearch_container.security_group_id
#   source_security_group_id = module.opensearch_nlb.security_group_id
#   description              = "Allow traffic from OpenSearch NLB"
# }

# ============================================================================
# OpenSearch Dashboards Service (DISABLED - OpenSearch is disabled)
# ============================================================================
#
# OpenSearch Dashboards has been disabled along with OpenSearch.
# To re-enable, uncomment the resources below and ensure OpenSearch is enabled.
#
# resource "aws_lb_target_group" "dashboards" {
#   count       = var.route53_zone_id != null ? 1 : 0
#   name        = "${local.name}-dashboards-tg"
#   port        = 5601
#   protocol    = "HTTP"
#   target_type = "ip"
#   vpc_id      = module.networking.vpc_id
#
#   health_check {
#     enabled             = true
#     interval            = 30
#     path                = "/api/status"
#     matcher             = "200-399"
#     healthy_threshold   = 2
#     unhealthy_threshold = 5
#   }
#
#   tags = merge(local.tags, {
#     Name = "${local.name}-dashboards-tg"
#   })
# }
#
# resource "aws_lb_listener_rule" "dashboards" {
#   count        = var.route53_zone_id != null && var.domain_name != null && var.enable_load_balancer ? 1 : 0
#   listener_arn = var.enable_https ? module.ecs_service.https_listener_arn : module.ecs_service.http_listener_arn
#   priority     = 100
#
#   action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.dashboards[0].arn
#   }
#
#   condition {
#     host_header {
#       values = ["${var.dashboards_subdomain}.${var.domain_name}"]
#     }
#   }
# }
#
# module "opensearch_dashboards" {
#   source = "../../modules/opensearch_dashboards"
#
#   name                  = local.name
#   vpc_id                = module.networking.vpc_id
#   subnet_ids            = module.networking.private_subnet_ids
#   ecs_cluster_name      = module.ecs_service.cluster_name
#   opensearch_endpoint   = "http://${module.opensearch_nlb.nlb_dns_name}:9200"
#   alb_security_group_ids = var.enable_load_balancer && module.ecs_service.alb_security_group_id != null ? [module.ecs_service.alb_security_group_id] : []
#   target_group_arn      = var.route53_zone_id != null ? aws_lb_target_group.dashboards[0].arn : null
#   container_image        = "opensearchproject/opensearch-dashboards:2.11.0"
#   cpu                    = 256
#   memory                 = 512
#   log_retention_in_days  = var.log_retention_in_days
#   tags                   = local.tags
#
#   depends_on = [module.opensearch_nlb, module.ecs_service]
# }

# ============================================================================
# Route53 Records for Subdomains
# ============================================================================
# API subdomain (api.shelfshack.com)
resource "aws_route53_record" "api" {
  count   = var.route53_zone_id != null && var.domain_name != null && var.enable_load_balancer ? 1 : 0
  zone_id = var.route53_zone_id
  name    = "${var.api_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = data.aws_lb.alb[0].dns_name
    zone_id                = data.aws_lb.alb[0].zone_id
    evaluate_target_health = true
  }
}

# Data source to get ALB zone ID
data "aws_lb" "alb" {
  count = var.route53_zone_id != null && var.enable_load_balancer ? 1 : 0
  name  = "${local.name}-alb"
}

# OpenSearch subdomain (search.shelfshack.com) - DISABLED
# resource "aws_route53_record" "opensearch" {
#   count   = var.route53_zone_id != null && var.domain_name != null ? 1 : 0
#   zone_id = var.route53_zone_id
#   name    = "${var.opensearch_subdomain}.${var.domain_name}"
#   type    = "CNAME"
#   ttl     = 60
#   records = [module.opensearch_nlb.nlb_dns_name]
# }

# Dashboards subdomain (dashboards.shelfshack.com) - DISABLED
# resource "aws_route53_record" "dashboards" {
#   count   = var.route53_zone_id != null && var.domain_name != null && var.enable_load_balancer ? 1 : 0
#   zone_id = var.route53_zone_id
#   name    = "${var.dashboards_subdomain}.${var.domain_name}"
#   type    = "A"
#
#   alias {
#     name                   = data.aws_lb.alb[0].dns_name
#     zone_id                = data.aws_lb.alb[0].zone_id
#     evaluate_target_health = true
#   }
# }
