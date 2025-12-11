variable "aws_region" {
  description = "AWS region for this environment."
  type        = string
}

variable "project" {
  description = "Project name used for tagging and resource naming."
  type        = string
  default     = "rentify"
}

variable "environment" {
  description = "Environment identifier (dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "default_tags" {
  description = "Additional tags automatically merged onto every resource."
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to deploy subnets into."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets."
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs for private subnets."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "enable_nat_gateway" {
  description = "Toggle NAT gateway creation."
  type        = bool
  default     = true
}

variable "enable_ssm_endpoints" {
  description = "Create VPC interface endpoints for SSM/SSM Messages so ECS Exec works without public internet."
  type        = bool
  default     = true
}

variable "enable_bastion_host" {
  description = "Provision an SSM-enabled bastion host for administrative access."
  type        = bool
  default     = false
}

variable "bastion_instance_type" {
  description = "Instance type used for the bastion host."
  type        = string
  default     = "t3.micro"
}

variable "bastion_allow_ssh_cidr_blocks" {
  description = "Optional CIDRs allowed to SSH directly to the bastion (leave empty to use SSM only)."
  type        = list(string)
  default     = []
}

variable "image_tag_mutability" {
  description = "Whether ECR tags can be overwritten."
  type        = string
  default     = "MUTABLE"
}

variable "scan_ecr_on_push" {
  description = "Enable image scanning on push."
  type        = bool
  default     = true
}

variable "container_image_tag" {
  description = "Docker image tag to deploy."
  type        = string
  default     = "latest"
}

variable "container_port" {
  description = "Application container port."
  type        = number
  default     = 3000
}

variable "cpu" {
  description = "Fargate CPU units (e.g. 256, 512, 1024)."
  type        = number
  default     = 512
}

variable "memory" {
  description = "Fargate memory in MB."
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Desired number of running tasks."
  type        = number
  default     = 2
}

variable "assign_public_ip" {
  description = "Assign public IPs to tasks."
  type        = bool
  default     = false
}

variable "enable_load_balancer" {
  description = "Toggle creation of the Application Load Balancer."
  type        = bool
  default     = true
}

variable "service_subnet_ids" {
  description = "Optional override for the subnets used by the ECS service (defaults to private when the ALB is enabled, public otherwise)."
  type        = list(string)
  default     = []
}

variable "app_environment" {
  description = "Key/value environment variables for the container."
  type        = map(string)
  default     = {}
}

variable "app_secrets" {
  description = "List of secrets passed to the container."
  type = list(object({
    name       = string
    value_from = string
  }))
  default = []
}

variable "health_check_path" {
  description = "Application health check endpoint."
  type        = string
  default     = "/health"
}

variable "listener_port" {
  description = "External HTTP listener port."
  type        = number
  default     = 80
}

variable "enable_https" {
  description = "Enable HTTPS listener."
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for creating a DNS record in front of the ALB."
  type        = string
  default     = null
}

variable "route53_record_name" {
  description = "Record name created inside the hosted zone (can be relative or FQDN)."
  type        = string
  default     = null
}

variable "certificate_arn" {
  description = "ACM certificate used for HTTPS."
  type        = string
  default     = null
}

variable "domain_name" {
  description = "Base domain name (e.g., 'shelfshack.com') for creating subdomains"
  type        = string
  default     = null
}

variable "api_subdomain" {
  description = "Subdomain for API (e.g., 'api' for api.shelfshack.com)"
  type        = string
  default     = "api"
}

variable "opensearch_subdomain" {
  description = "Subdomain for OpenSearch (e.g., 'search' for search.shelfshack.com)"
  type        = string
  default     = "search"
}

variable "dashboards_subdomain" {
  description = "Subdomain for OpenSearch Dashboards (e.g., 'dashboards' for dashboards.shelfshack.com)"
  type        = string
  default     = "dashboards"
}

variable "log_retention_in_days" {
  description = "CloudWatch Logs retention."
  type        = number
  default     = 30
}

variable "deployment_maximum_percent" {
  description = "Max running tasks during deployment."
  type        = number
  default     = 200
}

variable "deployment_minimum_healthy_percent" {
  description = "Min healthy tasks during deployment."
  type        = number
  default     = 100
}

variable "enable_execute_command" {
  description = "Enable ECS Exec."
  type        = bool
  default     = true
}

variable "force_new_deployment" {
  description = "Force ECS service to roll tasks on every apply."
  type        = bool
  default     = true
}

variable "task_role_managed_policies" {
  description = "Managed policies attached to the task IAM role."
  type        = list(string)
  default     = []
}

variable "extra_service_security_group_ids" {
  description = "Extra security groups attached to ECS service ENIs."
  type        = list(string)
  default     = []
}

variable "command" {
  description = "Override default container command."
  type        = list(string)
  default     = null
}

variable "db_name" {
  description = "RDS database name."
  type        = string
  default     = "shelfshack"
}

variable "db_master_username" {
  description = "Master username for the RDS instance."
  type        = string
  default     = "dbadmin_shelfshack"
}

variable "db_master_password" {
  description = "Master password for the RDS instance (lowercase/legacy input)."
  type        = string
  sensitive   = true
  default     = null
}

variable "DB_MASTER_PASSWORD" {
  description = "Master password for the RDS instance (uppercase-friendly for CI)."
  type        = string
  sensitive   = true
  default     = null
}

variable "db_master_password_secret_arn" {
  description = "Optional ARN of AWS Secrets Manager secret containing the RDS master password. If provided, this takes precedence over environment variables. Secret should contain a key named 'password' or be a plain text secret."
  type        = string
  default     = null
}

variable "db_allocated_storage" {
  description = "Allocated storage (GB)."
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "17.6"
}

variable "db_multi_az" {
  description = "Enable RDS multi-AZ."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Number of days to retain backups."
  type        = number
  default     = 0
}

variable "db_skip_final_snapshot" {
  description = "Skip final snapshot on destroy."
  type        = bool
  default     = true
}

variable "db_deletion_protection" {
  description = "Enable deletion protection."
  type        = bool
  default     = false
}

variable "db_apply_immediately" {
  description = "Apply DB modifications immediately."
  type        = bool
  default     = true
}

variable "db_publicly_accessible" {
  description = "Expose DB publicly."
  type        = bool
  default     = false
}

# OpenSearch variables
variable "opensearch_domain_name" {
  description = "Name of the OpenSearch domain"
  type        = string
  default     = "shelfshack-search"
}

variable "opensearch_engine_version" {
  description = "OpenSearch engine version (e.g., 'OpenSearch_2.11', 'OpenSearch_2.13')"
  type        = string
  default     = "OpenSearch_2.11"
}

variable "opensearch_instance_type" {
  description = "Instance type for OpenSearch data nodes (e.g., 't3.small.search', 't3.medium.search')"
  type        = string
  default     = "t3.small.search"
}

variable "opensearch_instance_count" {
  description = "Number of instances in the OpenSearch cluster (1-2 for dev, free tier friendly)"
  type        = number
  default     = 1
}

variable "opensearch_iam_role_arns" {
  description = "List of IAM role ARNs allowed to access OpenSearch (e.g., RentDeployRole ARN). The ECS task role is automatically added."
  type        = list(string)
  default     = []
  # Example: default = ["arn:aws:iam::ACCOUNT_ID:role/RentDeployRole"]
  # TODO: Replace ACCOUNT_ID with your AWS account ID and ensure RentDeployRole exists
}

variable "opensearch_master_user_arn" {
  description = "Optional IAM user/role ARN to use as the OpenSearch master user. If not provided, uses the first role from opensearch_iam_role_arns"
  type        = string
  default     = null
}

variable "opensearch_allowed_cidr_blocks" {
  description = "Optional list of CIDR blocks allowed to access OpenSearch (e.g., your IP for Kibana/Dashboards access)"
  type        = list(string)
  default     = []
  # Example: default = ["YOUR_IP_ADDRESS/32"]
  # TODO: Replace YOUR_IP_ADDRESS with your public IP for Kibana access
}

variable "opensearch_ebs_volume_size" {
  description = "EBS volume size in GB for each OpenSearch node"
  type        = number
  default     = 10
}

variable "opensearch_ebs_volume_type" {
  description = "EBS volume type for OpenSearch (gp3, gp2, etc.)"
  type        = string
  default     = "gp3"
}

variable "opensearch_enable_cloudwatch_logs" {
  description = "Enable CloudWatch logging for OpenSearch (INDEX_SLOW_LOGS, SEARCH_SLOW_LOGS)"
  type        = bool
  default     = false
}

variable "opensearch_log_retention_in_days" {
  description = "CloudWatch log retention in days for OpenSearch"
  type        = number
  default     = 7
}

variable "opensearch_create_service_linked_role" {
  description = "Whether to create the IAM service-linked role for OpenSearch (create once per AWS account)"
  type        = bool
  default     = true
}
