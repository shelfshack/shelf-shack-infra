aws_region   = "us-east-1"
project      = "shelfshack"
environment  = "prod"

# Production VPC CIDR (different from dev to avoid conflicts)
vpc_cidr = "10.1.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnet_cidrs  = ["10.1.0.0/24", "10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24", "10.1.12.0/24"]
# Bastion host disabled - can be enabled in future if needed
# enable_bastion_host  = true
# bastion_allow_ssh_cidr_blocks = []
enable_bastion_host  = false
bastion_allow_ssh_cidr_blocks = []

container_image_tag = "latest"
container_port      = 8000
desired_count       = 3  # Production: Higher availability with multiple instances
# Production: More CPU and memory for better performance
cpu                 = 2048   # Production: More CPU
memory              = 4096   # Production: More memory
enable_load_balancer = false  # Production: Enable ALB
route53_zone_id     = null  # Set to your Route53 hosted zone ID
route53_record_name = null
enable_https        = false  # Production: Enable HTTPS
certificate_arn     = null  # Set to your ACM certificate ARN
domain_name         = null  # Set to your domain name (e.g., "shelfshack.com")

app_environment = {
  NODE_ENV = "production"
  DB_MANAGE_COMMAND = "--create --bootstrap"
  DB_BOOTSTRAP = "false"
  SYNC_MISSING_TO_OPENSEARCH="true"
  PASSWORD_RESET_TOKEN_EXPIRE_MINUTES=60
  S3_BUCKET_NAME="shelfshack-prod-uploads"
  S3_REGION="us-east-1"
  S3_PUBLIC_BASE_URL="https://shelfshack-prod-uploads.s3.us-east-1.amazonaws.com/"
  S3_PROFILE_PREFIX="profile_photos"
  S3_ITEM_PREFIX="item_images"
  S3_USE_PATH_STYLE="false"
  ACCESS_TOKEN_EXPIRE_MINUTES=30
  
  # Note: WebSocket notification broadcasting variables (CONNECTIONS_TABLE, WEBSOCKET_API_ENDPOINT, AWS_REGION)
  # are automatically set in main.tf from the websocket_lambda module and API Gateway resources.
  # You don't need to set them here in terraform.tfvars.
}

force_new_deployment = false  # Production: Don't force deployment on every apply

app_secrets = [
  {
    name       = "DATABASE_URL"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:shelfshack/prod/db-url-XXXXXX:DATABASE_URL::"
  },
  {
    name       = "GOOGLE_CLIENT_ID"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:google_api_client_id-XXXXXX:GOOGLE_CLIENT_ID::"
  },
  {
    name       = "SMTP_SERVER"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:smtp_secret-XXXXXX:SMTP_SERVER::"
  },
  {
    name       = "SMTP_PORT"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:smtp_secret-XXXXXX:SMTP_PORT::"
  },
  {
    name       = "SMTP_USERNAME"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:smtp_secret-XXXXXX:SMTP_USERNAME::"
  },
  {
    name       = "SMTP_PASSWORD"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:smtp_secret-XXXXXX:SMTP_PASSWORD::"
  },
  {
    name       = "EMAILS_FROM_EMAIL"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:smtp_secret-XXXXXX:EMAILS_FROM_EMAIL::"
  },
  {
    name       = "FRONTEND_BASE_URL"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:smtp_secret-XXXXXX:FRONTEND_BASE_URL::"
  },
  {
    name       = "STRIPE_SECRET_KEY"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:stripe_secret_key-XXXXXX:STRIPE_SECRET_KEY::"
  }
]

# RDS inputs (do not commit real passwords; set TF_VAR_db_master_password via secrets/provider)
db_master_username  = "dbadmin_shelfshack"
# db_master_password is intentionally unset; provide it via TF_VAR_DB_MASTER_PASSWORD in CI/secrets.
# Recommended: Use AWS Secrets Manager for production
# db_master_password_secret_arn = "arn:aws:secretsmanager:us-east-1:506852294788:secret:shelfshack/prod/db-password-XXXXXX"
db_allocated_storage = 100  # Production: More storage
db_engine_version    = "17.6"
db_multi_az          = true  # Production: Enable multi-AZ for high availability
db_backup_retention_days = 30  # Production: Retain backups for 30 days
db_skip_final_snapshot   = false  # Production: Create final snapshot before deletion
db_deletion_protection   = true  # Production: Enable deletion protection
db_apply_immediately     = false  # Production: Apply during maintenance window
db_publicly_accessible   = false

# Replace ACCOUNT_ID with your AWS account ID
opensearch_iam_role_arns = [
  "arn:aws:iam::506852294788:role/shelfshackDeployRole"
]

# Optional: Add your IP for Kibana access (leave empty if not needed)
# Example: opensearch_allowed_cidr_blocks = ["1.2.3.4/32"]
opensearch_allowed_cidr_blocks = []

# Set to false if the OpenSearch service-linked role already exists in your account
# (The role can only be created once per AWS account and requires special IAM permissions)
opensearch_create_service_linked_role = false

# OpenSearch EC2 Configuration
opensearch_ec2_security_disabled = true
enable_opensearch_ec2 = true
# Use stable version (2.11.0)
opensearch_ec2_image   = "opensearchproject/opensearch"
opensearch_ec2_version = "2.11.0"
opensearch_ec2_instance_type = "m7i-flex.large"  # 8GB RAM, 2 vCPU
opensearch_ec2_java_heap_size = "2g"  # Optimal heap for m7i-flex.large (8GB RAM)

# WebSocket API Gateway and Lambda Configuration
websocket_stage_name = "production"
# Path to Lambda source file - relative path from envs/prod directory
# Lambda code is now part of the infra repo at: ../../lambda/websocket_proxy.py
websocket_lambda_source_file = "../../lambda/websocket_proxy.py"
# Path to Lambda requirements.txt - relative path from envs/prod directory
websocket_lambda_requirements_file = "../../lambda/requirements.txt"
# Optional: Override backend URL (defaults to ALB URL if available)
# websocket_backend_url = "https://api.yourdomain.com"

# HTTP API Gateway Configuration
http_api_stage_name = "production"
# Optional: Override backend URL (defaults to ALB DNS or ECS public IP)
# http_api_backend_url = "https://api.yourdomain.com"
http_api_backend_ip = null
http_api_timeout_milliseconds = 30000
http_api_cors_origins = ["*"]  # Update with your frontend domain for production
http_api_cors_methods = ["*"]
http_api_cors_headers = ["*"]
http_api_cors_max_age = 300
http_api_throttle_rate_limit = 100
http_api_throttle_burst_limit = 50

# Deploy Role Configuration
deploy_role_name = "shelfshackDeployRole"

# Log retention
log_retention_in_days = 90  # Production: Retain logs for 90 days

# Deployment settings
deployment_maximum_percent = 200
deployment_minimum_healthy_percent = 50  # Production: Allow rolling updates

