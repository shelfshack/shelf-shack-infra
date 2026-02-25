terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
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

# External data source to get ECS task public IP (using AWS CLI)
# This data source runs during terraform plan/apply and fetches the CURRENT running task's IP
# It waits up to 10 minutes for the task to be ready with a public IP assigned
# Improved error handling and retry logic for better reliability
data "external" "ecs_task_public_ip" {
  count = !var.enable_load_balancer ? 1 : 0
  program = ["bash", "-c", <<-EOT
    set -euo pipefail  # Exit on error, undefined vars, pipe failures
    
    CLUSTER="${module.ecs_service.cluster_name}"
    SERVICE="${module.ecs_service.service_name}"
    TASK_DEF_ARN="${module.ecs_service.task_definition_arn}"
    
    # Retry configuration: wait up to 10 minutes for task to be ready with public IP
    # Increased from 5 minutes for better reliability during deployments
    MAX_RETRIES=120
    RETRY_DELAY=5
    RETRY_COUNT=0
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
      # Get all running tasks for the service
      TASK_ARNS=$(aws ecs list-tasks \
        --cluster "$CLUSTER" \
        --service-name "$SERVICE" \
        --desired-status RUNNING \
        --query 'taskArns[]' \
        --output text 2>/dev/null || echo "")
      
      if [ -z "$TASK_ARNS" ]; then
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
          echo "Waiting for ECS tasks to start... (attempt $RETRY_COUNT/$MAX_RETRIES)" >&2
          sleep $RETRY_DELAY
          continue
        else
          echo "ERROR: No running tasks found for service $SERVICE in cluster $CLUSTER after $MAX_RETRIES attempts" >&2
          echo "This may indicate:" >&2
          echo "  1. ECS service is not running or has no tasks" >&2
          echo "  2. Tasks are failing to start (check ECS service events)" >&2
          echo "  3. Network connectivity issues" >&2
          echo '{"public_ip":"","error":"No running tasks found after waiting","cluster":"'$CLUSTER'","service":"'$SERVICE'"}'
          exit 1  # Exit with error to fail Terraform apply
        fi
      fi
      
      # Get task details and filter by current task definition ARN
      # Sort by creation time (newest first) to get the latest deployment
      NEWEST_TASK_ARN=""
      NEWEST_CREATED_AT=""
      
      for TASK_ARN in $TASK_ARNS; do
        # Get task definition ARN directly using AWS CLI query (more reliable than JSON parsing)
        TASK_DEF=$(aws ecs describe-tasks \
          --cluster "$CLUSTER" \
          --tasks "$TASK_ARN" \
          --query 'tasks[0].taskDefinitionArn' \
          --output text 2>/dev/null || echo "")
        
        if [ -z "$TASK_DEF" ] || [ "$TASK_DEF" == "None" ] || [ "$TASK_DEF" == "null" ]; then
          continue
        fi
        
        # Compare task definition ARNs (exact match)
        if [ "$TASK_DEF" != "$TASK_DEF_ARN" ]; then
          continue
        fi
        
        # Get creation time (startedAt timestamp) directly using AWS CLI query
        CREATED_AT=$(aws ecs describe-tasks \
          --cluster "$CLUSTER" \
          --tasks "$TASK_ARN" \
          --query 'tasks[0].startedAt' \
          --output text 2>/dev/null || echo "")
        
        if [ -z "$CREATED_AT" ] || [ "$CREATED_AT" == "None" ] || [ "$CREATED_AT" == "null" ]; then
          continue
        fi
        
        # ISO 8601 timestamps are lexicographically sortable, so we can compare them directly
        # Keep track of newest task (lexicographically largest timestamp = newest)
        if [ -z "$NEWEST_CREATED_AT" ] || [ "$CREATED_AT" \> "$NEWEST_CREATED_AT" ]; then
          NEWEST_CREATED_AT=$CREATED_AT
          NEWEST_TASK_ARN=$TASK_ARN
        fi
      done
      
      if [ -z "$NEWEST_TASK_ARN" ]; then
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
          echo "Waiting for task with matching task definition... (attempt $RETRY_COUNT/$MAX_RETRIES)" >&2
          sleep $RETRY_DELAY
          continue
        else
          echo "ERROR: No task found matching task definition $TASK_DEF_ARN after $MAX_RETRIES attempts" >&2
          echo "This may indicate a deployment is in progress or tasks are using an older task definition." >&2
          echo '{"public_ip":"","error":"No task found matching current task definition after waiting","task_def_arn":"'$TASK_DEF_ARN'"}'
          exit 1  # Exit with error to fail Terraform apply
        fi
      fi
      
      # Get ENI ID from the newest matching task
      ENI_ID=$(aws ecs describe-tasks \
        --cluster "$CLUSTER" \
        --tasks "$NEWEST_TASK_ARN" \
        --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
        --output text 2>/dev/null || echo "")
      
      if [ -z "$ENI_ID" ] || [ "$ENI_ID" == "None" ]; then
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
          echo "Waiting for ENI to be attached... (attempt $RETRY_COUNT/$MAX_RETRIES)" >&2
          sleep $RETRY_DELAY
          continue
        else
          echo "ERROR: No ENI found for task $NEWEST_TASK_ARN after $MAX_RETRIES attempts" >&2
          echo "This may indicate the task is still initializing or network attachment failed." >&2
          echo '{"public_ip":"","error":"No ENI found for task after waiting","task_arn":"'$NEWEST_TASK_ARN'"}'
          exit 1  # Exit with error to fail Terraform apply
        fi
      fi
      
      # Get public IP from ENI
      PUBLIC_IP=$(aws ec2 describe-network-interfaces \
        --network-interface-ids "$ENI_ID" \
        --query 'NetworkInterfaces[0].Association.PublicIp' \
        --output text 2>/dev/null || echo "")
      
      if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" == "None" ] || [ "$PUBLIC_IP" == "null" ]; then
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
          echo "Waiting for public IP to be assigned... (attempt $RETRY_COUNT/$MAX_RETRIES)" >&2
          sleep $RETRY_DELAY
          continue
        else
          echo "ERROR: No public IP found for ENI $ENI_ID after $MAX_RETRIES attempts" >&2
          echo "This may indicate:" >&2
          echo "  1. Task is in a private subnet without NAT Gateway" >&2
          echo "  2. Public IP assignment is delayed" >&2
          echo "  3. Network interface configuration issue" >&2
          echo '{"public_ip":"","error":"No public IP found for ENI after waiting","eni_id":"'$ENI_ID'"}'
          exit 1  # Exit with error to fail Terraform apply
        fi
      fi
      
      # Success! We have a valid public IP
      echo "{\"public_ip\":\"$PUBLIC_IP\",\"task_arn\":\"$NEWEST_TASK_ARN\"}"
      exit 0
    done
    
    # If we get here, we've exhausted all retries
    echo "ERROR: Failed to get public IP after $MAX_RETRIES attempts ($((MAX_RETRIES * RETRY_DELAY / 60)) minutes)" >&2
    echo "Please check:" >&2
    echo "  1. ECS service status: aws ecs describe-services --cluster $CLUSTER --services $SERVICE" >&2
    echo "  2. Task status: aws ecs list-tasks --cluster $CLUSTER --service-name $SERVICE" >&2
    echo "  3. CloudWatch logs for the ECS service" >&2
    echo '{"public_ip":"","error":"Failed to get public IP after maximum retries","cluster":"'$CLUSTER'","service":"'$SERVICE'"}'
    exit 1  # Exit with error to fail Terraform apply
  EOT
  ]
  
  # Use task definition ARN as the primary trigger - only refresh when task definition changes
  # This prevents unnecessary refreshes on every apply
  query = {
    task_def_arn = module.ecs_service.task_definition_arn
    # Include service name and cluster for context, but task_def_arn is the key trigger
    service_name = module.ecs_service.service_name
    cluster_name = module.ecs_service.cluster_name
  }
  
  # Only refresh when task definition actually changes (new deployment)
  # This prevents unnecessary IP lookups on every apply
}

# Local value to determine the backend URL dynamically
locals {
  # Get public IP from external data source if ALB is disabled, otherwise use ALB DNS
  # Check if data source exists and has a valid IP
  ecs_public_ip = !var.enable_load_balancer && length(data.external.ecs_task_public_ip) > 0 ? (
    try(data.external.ecs_task_public_ip[0].result.public_ip, "") != "" && data.external.ecs_task_public_ip[0].result.public_ip != null ? 
      data.external.ecs_task_public_ip[0].result.public_ip : 
      null
  ) : null
  
  # Determine backend URL: priority: var.http_api_backend_url > ALB DNS > ECS public IP > fallback
  backend_url = var.http_api_backend_url != null ? var.http_api_backend_url : (
    var.enable_load_balancer && module.ecs_service.load_balancer_dns != null ? 
      "http://${module.ecs_service.load_balancer_dns}:${var.container_port}" : (
        local.ecs_public_ip != null ? 
          "http://${local.ecs_public_ip}:${var.container_port}" : 
          var.http_api_backend_ip != null ? "http://${var.http_api_backend_ip}:${var.container_port}" : null
      )
  )
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
  
  # Unified destruction control: allow_destruction takes precedence
  # If allow_destruction is set, use it. Otherwise, use inverse of prevent_resource_destruction (for backward compatibility)
  # Default: false (protected) - must explicitly set allow_destruction=true to destroy
  can_destroy = var.allow_destruction != null ? var.allow_destruction : (
    var.prevent_resource_destruction != null ? !var.prevent_resource_destruction : false
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
  enable_secretsmanager_endpoint = true
  tags                 = local.tags
  
  # Enable "create if not exists" to prevent duplicate VPCs when state is lost
  create_if_not_exists = true
  aws_region           = var.aws_region
}

# Bastion host disabled - can be enabled in future if needed
# module "bastion" {
#   source = "../../modules/bastion_host"
#
#   enabled               = var.enable_bastion_host
#   name                  = local.name
#   subnet_id             = module.networking.private_subnet_ids[0]
#   vpc_id                = module.networking.vpc_id
#   instance_type         = var.bastion_instance_type
#   allow_ssh_cidr_blocks = var.bastion_allow_ssh_cidr_blocks
#   tags                  = local.tags
# }

module "ecr" {
  source = "../../modules/ecr_repository"

  name                 = "${local.name}-repo"
  image_tag_mutability = var.image_tag_mutability
  scan_on_push         = var.scan_ecr_on_push
  tags                 = local.tags
  
  # Enable "create if not exists" behavior to prevent errors if repo already exists
  create_if_not_exists = true
  aws_region           = var.aws_region
  force_delete         = true  # Allow destroy even with images
}

# S3 Bucket for application uploads
module "s3_uploads" {
  source = "../../modules/s3_uploads"

  bucket_name = lookup(var.app_environment, "S3_BUCKET_NAME", "${local.name}-uploads")
  item_prefix  = lookup(var.app_environment, "S3_ITEM_PREFIX", "item_images")
  profile_prefix = lookup(var.app_environment, "S3_PROFILE_PREFIX", "profile_photos")
  
  enable_versioning = false  # Disable versioning for cost savings (can enable if needed)
  lifecycle_days    = 0      # Disable lifecycle rules (can enable if needed)
  
  # Grant ECS task role permissions to upload files
  ecs_task_role_arn = module.ecs_service.task_role_arn
  
  # CORS: Allow uploads from frontend domains
  cors_allowed_origins = concat(
    var.http_api_cors_origins,
    ["https://shelfshack.com", "https://www.shelfshack.com"]
  )
  
  tags = local.tags
  
  depends_on = [module.ecs_service]
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
    # Add WebSocket notification broadcasting variables (CONNECTIONS_TABLE, WEBSOCKET_API_ENDPOINT, AWS_REGION)
    # NOTE: This mirrors the dev environment configuration so that backend can:
    #  - Read CONNECTIONS_TABLE to find active WebSocket connections in DynamoDB
    #  - Read WEBSOCKET_API_ENDPOINT to construct the API Gateway Management API endpoint
    #  - Read AWS_REGION for boto3 clients
    [
      {
        name  = "CONNECTIONS_TABLE"
        value = "${local.name}-websocket-connections"
      },
      {
        name  = "WEBSOCKET_API_ENDPOINT"
        # Use HTTPS endpoint for API Gateway Management API (Lambda/backend will convert if needed)
        value = "https://${aws_apigatewayv2_api.websocket.id}.execute-api.${var.aws_region}.amazonaws.com/${var.websocket_stage_name}"
      },
      {
        name  = "AWS_REGION"
        value = var.aws_region
      }
    ],
    # Add OpenSearch configuration if EC2 OpenSearch is enabled
    var.enable_opensearch_ec2 ? concat([
      {
        name  = "OPENSEARCH_HOST"
        value = module.opensearch_ec2[0].opensearch_host
      },
      {
        name  = "OPENSEARCH_PORT"
        value = "9200"
      }
    ]) : []
  )
  secrets                     = var.app_secrets
  health_check_path           = var.health_check_path
  listener_port               = var.listener_port
  enable_https                = var.enable_https
  certificate_arn             = var.certificate_arn
  route53_zone_id             = var.route53_zone_id
  route53_record_name          = var.route53_record_name
  log_retention_in_days       = var.log_retention_in_days
  deployment_maximum_percent  = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  enable_execute_command             = var.enable_execute_command
  force_new_deployment               = var.force_new_deployment
  task_role_managed_policies         = var.task_role_managed_policies
  s3_bucket_name                     = lookup(var.app_environment, "S3_BUCKET_NAME", null)
  additional_service_security_group_ids = var.extra_service_security_group_ids
  command                              = var.command
  # Temporarily disabled AWS OpenSearch Service - using containerized version instead
  # opensearch_domain_arn                = module.opensearch.domain_arn
  # enable_opensearch_access             = true
  opensearch_domain_arn                = null
  enable_opensearch_access             = false
  tags                                 = local.tags

  depends_on = [module.rds, module.networking]
  # Note: OpenSearch is disabled - backend will use PostgreSQL for search
}

# RDS deletion protection disable resource - must be created before RDS module
# This ensures the destroy provisioner runs BEFORE RDS is destroyed
resource "null_resource" "rds_disable_deletion_protection" {
  # Always create this resource so it exists in state and can run destroy provisioner
  # Creation provisioner ensures it's always created
  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      echo "RDS deletion protection manager resource created."
      echo "This resource will disable RDS deletion protection during destroy."
    EOT
  }
  
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -e
      INSTANCE="shelfshack-prod-postgres"
      REGION="us-east-1"
      
      echo "=========================================="
      echo "Disabling RDS deletion protection"
      echo "=========================================="
      echo "Checking RDS deletion protection for instance: $INSTANCE in region: $REGION"

      # Check if RDS instance exists and get current DeletionProtection flag
      STATUS=$(aws rds describe-db-instances \
        --db-instance-identifier "$INSTANCE" \
        --region "$REGION" \
        --query 'DBInstances[0].DeletionProtection' \
        --output text 2>/dev/null || echo "not-found")

      if [ "$STATUS" = "not-found" ] || [ "$STATUS" = "None" ]; then
        echo "RDS instance $INSTANCE not found or already deleted. Skipping deletion protection update."
        exit 0
      fi

      echo "Current deletion protection status for $INSTANCE: $STATUS"

      if [ "$STATUS" = "true" ]; then
        echo "Disabling RDS deletion protection for $INSTANCE..."
        aws rds modify-db-instance \
          --db-instance-identifier "$INSTANCE" \
          --no-deletion-protection \
          --apply-immediately \
          --region "$REGION" || {
            echo "WARNING: Failed to disable deletion protection. Continuing anyway..." >&2
            exit 0  # Don't fail - let Terraform try to destroy anyway
          }

        echo "Waiting for deletion protection to be disabled..."
        # Poll until DeletionProtection is reported as false, with a sensible timeout
        ATTEMPTS=0
        MAX_ATTEMPTS=30  # ~5 minutes max (30 * 10s)
        while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
          CURRENT=$(aws rds describe-db-instances \
            --db-instance-identifier "$INSTANCE" \
            --region "$REGION" \
            --query 'DBInstances[0].DeletionProtection' \
            --output text 2>/dev/null || echo "false")

          echo "  Poll attempt $((ATTEMPTS + 1))/$MAX_ATTEMPTS: DeletionProtection=$CURRENT"

          if [ "$CURRENT" = "false" ]; then
            echo "✓ Deletion protection successfully disabled for $INSTANCE."
            exit 0
          fi

          ATTEMPTS=$((ATTEMPTS + 1))
          sleep 10
        done

        echo "WARNING: Timed out waiting for deletion protection to be disabled, but continuing destroy..." >&2
        exit 0  # Don't fail - let Terraform try anyway
      else
        echo "✓ Deletion protection already disabled for $INSTANCE. Continuing destroy."
      fi
    EOT
  }
  
  triggers = {
    can_destroy = tostring(local.can_destroy)
    rds_id      = "shelfshack-prod-postgres"  # Use fixed name to avoid dependency cycle
  }
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
  final_snapshot_identifier = var.db_final_snapshot_identifier
  # Deletion protection: false when allow_destruction=true, otherwise use var.db_deletion_protection
  deletion_protection        = local.can_destroy ? false : var.db_deletion_protection
  apply_immediately          = var.db_apply_immediately
  publicly_accessible        = var.db_publicly_accessible
  tags                       = local.tags
  
  # Resilience: Check if resources exist before creating
  create_if_not_exists = true
  aws_region           = var.aws_region
  
  # Note: depends_on on modules doesn't guarantee destroy order
  # The destroy script handles RDS deletion protection disable before terraform destroy
}


resource "aws_security_group_rule" "rds_from_ecs" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.rds.security_group_id
  source_security_group_id = module.ecs_service.service_security_group_id
}

# Bastion host disabled - can be enabled in future if needed
# resource "aws_security_group_rule" "rds_from_bastion" {
#   count                    = var.enable_bastion_host ? 1 : 0
#   type                     = "ingress"
#   from_port                = 5432
#   to_port                  = 5432
#   protocol                 = "tcp"
#   security_group_id        = module.rds.security_group_id
#   source_security_group_id = module.bastion.security_group_id
# }

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

# Bastion host disabled - can be enabled in future if needed
# resource "aws_security_group_rule" "opensearch_from_bastion" {
#   count                    = var.enable_opensearch_ec2 && var.enable_bastion_host ? 1 : 0
#   type                     = "ingress"
#   from_port                = 22
#   to_port                  = 22
#   protocol                 = "tcp"
#   security_group_id        = module.opensearch_ec2[0].security_group_id
#   source_security_group_id = module.bastion.security_group_id
#   description              = "SSH from bastion host"
# }

# ============================================================================
# AWS OpenSearch Service (TEMPORARILY DISABLED - Using containerized version)
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
# WebSocket API Gateway and Lambda Proxy
# ============================================================================
# Note: API Gateway WebSocket API and Lambda function for chat WebSocket proxy
# This enables WebSocket connections through API Gateway to work with AWS Amplify

# API Gateway WebSocket API
resource "aws_apigatewayv2_api" "websocket" {
  name                       = "${local.name}-websocket"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
  
  tags = local.tags
  
  lifecycle {
    create_before_destroy = true
    # Ignore changes to tags that don't affect functionality
    ignore_changes = [
      tags["ManagedBy"]  # Allow tag updates without recreation
    ]
  }
}

# API Gateway WebSocket Stage
resource "aws_apigatewayv2_stage" "websocket" {
  api_id      = aws_apigatewayv2_api.websocket.id
  name        = var.websocket_stage_name
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = 100
    throttling_burst_limit = 50
  }

  tags = local.tags
}

# WebSocket Lambda Proxy Module
module "websocket_lambda" {
  source = "../../modules/websocket_lambda"

  name                  = local.name
  connections_table_name = "${local.name}-websocket-connections"
  lambda_source_file    = var.websocket_lambda_source_file
  lambda_requirements_file = var.websocket_lambda_requirements_file
  # Use the same dynamically determined backend URL as HTTP API Gateway
  # Priority: var.websocket_backend_url > local.backend_url (auto-fetched) > fallback
  backend_url = var.websocket_backend_url != null ? var.websocket_backend_url : (
    local.backend_url != null ? local.backend_url : (
      var.enable_load_balancer && var.route53_zone_id != null && var.domain_name != null ? "https://${var.api_subdomain}.${var.domain_name}" : 
      "http://localhost:8000"
    )
  )
  api_gateway_id        = aws_apigatewayv2_api.websocket.id
  api_gateway_endpoint   = "https://${aws_apigatewayv2_api.websocket.id}.execute-api.${var.aws_region}.amazonaws.com/${var.websocket_stage_name}"
  additional_environment_variables = var.websocket_lambda_environment_variables
  tags                  = local.tags
  
  # Resilience: Check if resources exist before creating
  create_if_not_exists = true
  aws_region           = var.aws_region
}

# API Gateway WebSocket Routes
# $connect route
resource "aws_apigatewayv2_route" "connect" {
  api_id    = aws_apigatewayv2_api.websocket.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.websocket.id}"
}

# $disconnect route
resource "aws_apigatewayv2_route" "disconnect" {
  api_id    = aws_apigatewayv2_api.websocket.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.websocket.id}"
}

# $default route (for messages)
resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.websocket.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.websocket.id}"
}

# API Gateway WebSocket Integration
resource "aws_apigatewayv2_integration" "websocket" {
  api_id           = aws_apigatewayv2_api.websocket.id
  integration_type = "AWS_PROXY"
  integration_uri  = module.websocket_lambda.lambda_function_arn
}

# ============================================================================
# HTTP API Gateway for Backend (REST API Proxy)
# ============================================================================
# HTTP API Gateway that proxies requests to the ECS service
# This replaces the manually created API Gateway: shelfshack-backend-prod

# Validation: Ensure wildcard is not used with allow_credentials
locals {
  cors_has_wildcard = contains(var.http_api_cors_origins, "*")
  cors_validation_error = var.http_api_cors_allow_credentials && local.cors_has_wildcard ? (
    "ERROR: Cannot use wildcard '*' in http_api_cors_origins when http_api_cors_allow_credentials is true. " +
    "For Google OAuth and authenticated requests, you must specify explicit origins (e.g., ['https://shelfshack.com', 'https://www.shelfshack.com'])."
  ) : null
  
  # Validate throttle limits: burst_limit should be <= rate_limit
  throttle_validation_error = var.http_api_throttle_burst_limit > var.http_api_throttle_rate_limit ? (
    "ERROR: http_api_throttle_burst_limit (${var.http_api_throttle_burst_limit}) must be less than or equal to http_api_throttle_rate_limit (${var.http_api_throttle_rate_limit})."
  ) : null
}

# HTTP API Gateway
resource "aws_apigatewayv2_api" "backend" {
  name          = "${local.name}-backend"
  protocol_type = "HTTP"
  description   = "HTTP API Gateway for backend API proxy to ECS service"
  
  cors_configuration {
    allow_origins     = var.http_api_cors_origins
    allow_methods     = var.http_api_cors_methods
    allow_headers     = var.http_api_cors_headers
    allow_credentials = var.http_api_cors_allow_credentials
    max_age           = var.http_api_cors_max_age
  }
  
  tags = local.tags
  
  lifecycle {
    create_before_destroy = true
    # Ignore changes to description and tags that don't affect functionality
    ignore_changes = [
      description,
      tags["ManagedBy"]  # Allow tag updates without recreation
    ]
  }
}

# Fail fast if CORS configuration is invalid
resource "null_resource" "cors_validation" {
  count = local.cors_validation_error != null ? 1 : 0
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "${local.cors_validation_error}" >&2
      exit 1
    EOT
  }
  
  triggers = {
    cors_origins = join(",", var.http_api_cors_origins)
    allow_credentials = var.http_api_cors_allow_credentials
  }
}

# Fail fast if throttle configuration is invalid
resource "null_resource" "throttle_validation" {
  count = local.throttle_validation_error != null ? 1 : 0
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "${local.throttle_validation_error}" >&2
      exit 1
    EOT
  }
  
  triggers = {
    throttle_rate_limit = var.http_api_throttle_rate_limit
    throttle_burst_limit = var.http_api_throttle_burst_limit
  }
}

# Destroy protection: Only create this resource when protection is enabled
# When allow_destruction=true, this resource won't exist, so nothing blocks destroy
resource "null_resource" "destroy_protection" {
  count = local.can_destroy ? 0 : 1  # Only create when protection is needed
  
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -e
      # Check stored trigger value (from when resource was created/updated)
      STORED_VALUE="${try(self.triggers.can_destroy, "false")}"
      
      # Allow destruction if stored value says so
      if [ "$STORED_VALUE" = "true" ]; then
        echo "Destruction explicitly allowed (allow_destruction=true). Continuing destroy."
        exit 0
      fi
      
      # If we're here, the resource is being destroyed but allow_destruction wasn't set to true
      # This could be:
      # 1. An actual destroy operation (should be blocked)
      # 2. A count change during apply (should be allowed, but we can't detect this reliably)
      # 
      # To be safe, we'll block it and require the user to use the destroy script
      # which removes this resource from state first
      echo "ERROR: Resource destruction is prevented!" >&2
      echo "" >&2
      echo "This resource protects against accidental destruction." >&2
      echo "To allow destruction, use the destroy script (recommended):" >&2
      echo "  ./destroy.sh true [db_master_password]" >&2
      echo "" >&2
      echo "Or manually remove from state first:" >&2
      echo "  terraform state rm 'null_resource.destroy_protection[0]'" >&2
      echo "  terraform destroy -var='allow_destruction=true' -var='db_master_password=YOUR_PASSWORD' -auto-approve" >&2
      echo "" >&2
      exit 1
    EOT
  }
  
  depends_on = [
    aws_apigatewayv2_api.backend,
    aws_apigatewayv2_api.websocket,
    aws_iam_role.deploy_role,
    aws_route53_record.api
  ]
  
  triggers = {
    # Include resource IDs so this updates when resources change
    api_backend_id     = aws_apigatewayv2_api.backend.id
    api_websocket_id   = aws_apigatewayv2_api.websocket.id
    iam_role_name      = aws_iam_role.deploy_role.name
    # Force update when can_destroy changes
    can_destroy        = tostring(local.can_destroy)
  }
}

# HTTP API Gateway Stage
resource "aws_apigatewayv2_stage" "backend" {
  api_id      = aws_apigatewayv2_api.backend.id
  name        = var.http_api_stage_name
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = var.http_api_throttle_rate_limit
    throttling_burst_limit = var.http_api_throttle_burst_limit
  }

  tags = local.tags
  
  depends_on = [
    aws_apigatewayv2_api.backend,
    null_resource.cors_validation,
    null_resource.throttle_validation
  ]
  
  lifecycle {
    # Ensure stage is updated when API changes
    ignore_changes = []
  }
}

# Note: For HTTP APIs, CORS preflight (OPTIONS) requests are handled automatically
# by API Gateway when cors_configuration is set on the API.
# We don't need explicit OPTIONS routes or MOCK integrations for HTTP APIs.
# The CORS configuration in aws_apigatewayv2_api.backend will handle OPTIONS requests.

# HTTP API Gateway Integration (HTTP proxy to ECS service with {proxy} path)
resource "aws_apigatewayv2_integration" "backend" {
  api_id           = aws_apigatewayv2_api.backend.id
  integration_type = "HTTP_PROXY"
  # Integration URI with {proxy} placeholder - dynamically fetched from ECS service
  # Priority: var.http_api_backend_url > ALB DNS > ECS public IP (auto-fetched) > http_api_backend_ip
  integration_uri  = local.backend_url != null && local.backend_url != "" ? (
    # If URL already includes {proxy}, use as-is; otherwise append it
    can(regex("/\\{proxy\\}", local.backend_url)) ? local.backend_url : "${local.backend_url}/{proxy}"
  ) : (
    var.http_api_backend_ip != null ? "http://${var.http_api_backend_ip}:${var.container_port}/{proxy}" : "http://127.0.0.1:${var.container_port}/{proxy}"
  )
  integration_method = "ANY"
  timeout_milliseconds = var.http_api_timeout_milliseconds
  connection_type     = "INTERNET"
  
  depends_on = [
    data.external.ecs_task_public_ip,
    module.ecs_service
  ]
  
  lifecycle {
    # Integration URI can change (when IP changes), but integration should update in-place, not recreate
    create_before_destroy = false
    # Allow integration_uri to update when backend URL changes (e.g., new ECS task IP)
    # This ensures updates happen in-place without recreation
  }
}

# HTTP API Gateway Integration for root path (without {proxy})
# Note: OPTIONS requests for root path are handled by options_root route above
resource "aws_apigatewayv2_integration" "backend_root" {
  api_id           = aws_apigatewayv2_api.backend.id
  integration_type = "HTTP_PROXY"
  # Integration URI without {proxy} for root path - use base URL directly
  integration_uri  = var.http_api_backend_url != null ? (
    # If manual URL provided, remove /{proxy} if present, otherwise use as-is
    can(regex("/\\{proxy\\}", var.http_api_backend_url)) ? regex_replace(var.http_api_backend_url, "/\\{proxy\\}", "") : var.http_api_backend_url
  ) : (
    var.enable_load_balancer && module.ecs_service.load_balancer_dns != null ? 
      "http://${module.ecs_service.load_balancer_dns}:${var.container_port}" : (
        local.ecs_public_ip != null && local.ecs_public_ip != "" ? 
          "http://${local.ecs_public_ip}:${var.container_port}" : 
          var.http_api_backend_ip != null ? "http://${var.http_api_backend_ip}:${var.container_port}" : "http://127.0.0.1:${var.container_port}"
      )
  )
  integration_method = "ANY"
  timeout_milliseconds = var.http_api_timeout_milliseconds
  connection_type     = "INTERNET"
  
  depends_on = [
    data.external.ecs_task_public_ip,
    module.ecs_service
  ]
  
  lifecycle {
    # Integration URI can change (when IP changes), but integration should update in-place, not recreate
    create_before_destroy = false
    # Allow integration_uri to update when backend URL changes (e.g., new ECS task IP)
  }
}

# Lambda function to handle OPTIONS preflight requests
# This returns 200 OK so API Gateway can add CORS headers from cors_configuration
data "archive_file" "cors_options_lambda" {
  type        = "zip"
  source_file = "${path.module}/../../lambda/cors_options_handler.py"
  output_path = "${path.module}/cors_options_handler.zip"
}

resource "aws_lambda_function" "cors_options" {
  filename         = data.archive_file.cors_options_lambda.output_path
  function_name    = "${local.name}-cors-options-handler"
  role             = aws_iam_role.lambda_cors_options.arn
  handler          = "cors_options_handler.lambda_handler"
  runtime          = "python3.11"
  timeout          = 5
  memory_size      = 128
  source_code_hash = data.archive_file.cors_options_lambda.output_base64sha256

  tags = local.tags
}

# IAM role for CORS OPTIONS Lambda
resource "aws_iam_role" "lambda_cors_options" {
  name = "${local.name}-cors-options-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = local.tags
}

# Basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_cors_options_basic" {
  role       = aws_iam_role.lambda_cors_options.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "cors_options_apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cors_options.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.backend.execution_arn}/*/*"
}

# Lambda integration for OPTIONS requests
resource "aws_apigatewayv2_integration" "cors_options" {
  api_id           = aws_apigatewayv2_api.backend.id
  integration_type  = "AWS_PROXY"
  integration_uri   = aws_lambda_function.cors_options.invoke_arn
  integration_method = "POST"
}

# OPTIONS route for proxy paths - MUST be before ANY /{proxy+} route
resource "aws_apigatewayv2_route" "options_proxy" {
  api_id    = aws_apigatewayv2_api.backend.id
  route_key = "OPTIONS /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.cors_options.id}"
}

# OPTIONS route for root path - MUST be before ANY / route
resource "aws_apigatewayv2_route" "options_root" {
  api_id    = aws_apigatewayv2_api.backend.id
  route_key = "OPTIONS /"
  target    = "integrations/${aws_apigatewayv2_integration.cors_options.id}"
}

# HTTP API Gateway Route (catch-all proxy route)
# Note: OPTIONS routes above take precedence, so OPTIONS won't reach here
resource "aws_apigatewayv2_route" "backend_proxy" {
  api_id    = aws_apigatewayv2_api.backend.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.backend.id}"
}

# HTTP API Gateway Default Route (for root path, non-OPTIONS methods)
resource "aws_apigatewayv2_route" "backend_root" {
  api_id    = aws_apigatewayv2_api.backend.id
  route_key = "ANY /"
  target    = "integrations/${aws_apigatewayv2_integration.backend_root.id}"
}

# ============================================================================
# IAM Deploy Role
# ============================================================================
# IAM role for deployment operations (CI/CD, Terraform)
# This role is used by GitHub Actions and other deployment tools

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "deploy_role_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "deploy_role" {
  name               = var.deploy_role_name
  assume_role_policy = data.aws_iam_policy_document.deploy_role_assume.json
  
  tags = merge(local.tags, {
    Name = var.deploy_role_name
  })
  
  lifecycle {
    # Ignore tag changes that don't affect functionality
    ignore_changes = [
      tags["ManagedBy"]
    ]
  }
}

resource "aws_iam_role_policy" "deploy_role_consolidated" {
  name   = "${var.deploy_role_name}-consolidated-policy"
  role   = aws_iam_role.deploy_role.id
  policy = file("${path.module}/../../policies/deploy-role-consolidated-policy.json")
}

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
  
  lifecycle {
    # Allow alias target to update (when ALB changes) without recreation
    create_before_destroy = false
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

# ============================================================================
# Amplify Branch Environment Variables Management
# ============================================================================
# NOTE: The Amplify branch (main) is managed externally by Git/Amplify.
# Terraform only manages the environment variables - it does NOT create or destroy the branch.

# Merge user-provided and computed environment variables
locals {
  amplify_env_vars = merge(
    var.amplify_branch_environment_variables,
    # Add computed API endpoint if HTTP API Gateway is available
    var.amplify_app_id != null && var.amplify_prod_branch_name != null && aws_apigatewayv2_api.backend.id != null ? {
      API_BASE_URL_PRODUCTION = "https://${aws_apigatewayv2_api.backend.id}.execute-api.${var.aws_region}.amazonaws.com/${var.http_api_stage_name}"
      WS_API_ENDPOINT_PRODUCTION = "wss://${aws_apigatewayv2_api.websocket.id}.execute-api.${var.aws_region}.amazonaws.com/${var.websocket_stage_name}"
    } : {}
  )
  
  # Convert env vars map to JSON for AWS CLI
  amplify_env_vars_json = jsonencode(local.amplify_env_vars)
}

# Update Amplify branch environment variables using AWS CLI
# This does NOT create or destroy the branch - only updates env vars
# Update Amplify branch environment variables using AWS CLI
# This does NOT create or destroy the branch - only updates env vars
# Only updates when API Gateway endpoints actually change (not on every apply)
resource "null_resource" "amplify_env_vars" {
  count = var.amplify_app_id != null && var.amplify_prod_branch_name != null ? 1 : 0

  # Trigger update only when env vars actually change (API endpoints, not computed values)
  # This prevents unnecessary updates on every apply
  triggers = {
    # Only trigger on actual API Gateway ID changes, not on every apply
    http_api_id = aws_apigatewayv2_api.backend.id
    websocket_api_id = aws_apigatewayv2_api.websocket.id
    http_api_stage = var.http_api_stage_name
    websocket_stage = var.websocket_stage_name
    # Include custom env vars hash to detect manual changes
    custom_env_vars_hash = sha256(jsonencode(var.amplify_branch_environment_variables))
    app_id = var.amplify_app_id
    branch_name = var.amplify_prod_branch_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Updating Amplify branch environment variables..."
      aws amplify update-branch \
        --app-id ${var.amplify_app_id} \
        --branch-name ${var.amplify_prod_branch_name} \
        --environment-variables '${local.amplify_env_vars_json}' \
        --region ${var.aws_region} \
        && echo "✓ Environment variables updated successfully" \
        || echo "⚠ Failed to update environment variables (branch may not exist yet)"
    EOT
  }

  depends_on = [
    aws_apigatewayv2_api.backend,
    aws_apigatewayv2_api.websocket,
    aws_apigatewayv2_stage.backend,
    aws_apigatewayv2_stage.websocket
  ]
}

