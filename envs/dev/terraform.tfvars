aws_region   = "us-east-1"
project      = "shelfshack"
environment  = "dev"

availability_zones = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
# Bastion host disabled - can be enabled in future if needed
# enable_bastion_host  = true
# bastion_allow_ssh_cidr_blocks = []
enable_bastion_host  = false
bastion_allow_ssh_cidr_blocks = []

container_image_tag = "latest"
container_port      = 8000
desired_count       = 1  # Reduced from 2 to 1
# Increase memory to prevent OutOfMemoryError (Exit code 137)
# Fargate memory must be one of: 512, 1024, 2048, 3072, 4096, 5120, 6144, 7168, 8192, 9216, 10240, 11264, 12288, 13312, 14336, 15360, 16384, 17408, 18432, 19456, 20480, 21504, 22528, 23552, 24576, 25600, 26624, 27648, 28672, 29696, 30720
cpu                 = 1024   # Increased from 512 for better performance
memory              = 2048   # Increased from 1024 to prevent OutOfMemoryError
enable_load_balancer = false
# disable the ALB temporarily (e.g., free-tier accounts) by setting enable_load_balancer = false
route53_zone_id     = null
route53_record_name = null

app_environment = {
  NODE_ENV = "development"
  DB_MANAGE_COMMAND = "--create --bootstrap"
  DB_BOOTSTRAP = "true"
  SYNC_MISSING_TO_OPENSEARCH="true"
  PASSWORD_RESET_TOKEN_EXPIRE_MINUTES=60
  S3_BUCKET_NAME="shelfshack-dev-uploads"
  S3_REGION="us-east-1"
  S3_PUBLIC_BASE_URL="https://shelfshack-dev-uploads.s3.us-east-1.amazonaws.com/"
  S3_PROFILE_PREFIX="profile_photos"
  S3_ITEM_PREFIX="item_images"
  S3_USE_PATH_STYLE="false"
  ACCESS_TOKEN_EXPIRE_MINUTES=30
  
  # Note: WebSocket notification broadcasting variables (CONNECTIONS_TABLE, WEBSOCKET_API_ENDPOINT, AWS_REGION)
  # are automatically set in main.tf from the websocket_lambda module and API Gateway resources.
  # You don't need to set them here in terraform.tfvars.
}

force_new_deployment = true

app_secrets = [
  {
    name       = "DATABASE_URL"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:dev/shelfshack/backend_secrets-OEhS1N:DATABASE_URL::"
  },
  {
    name       = "GOOGLE_CLIENT_ID"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:dev/shelfshack/backend_secrets-OEhS1N:GOOGLE_CLIENT_ID::"
  },
  {
    name       = "SMTP_SERVER"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:dev/shelfshack/backend_secrets-OEhS1N:SMTP_SERVER::"
  },
  {
    name       = "SMTP_PORT"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:dev/shelfshack/backend_secrets-OEhS1N:SMTP_PORT::"
  },
  {
    name       = "SMTP_USERNAME"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:dev/shelfshack/backend_secrets-OEhS1N:SMTP_USERNAME::"
  },
  {
    name       = "SMTP_PASSWORD"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:dev/shelfshack/backend_secrets-OEhS1N:SMTP_PASSWORD::"
  },
  {
    name       = "EMAILS_FROM_EMAIL"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:dev/shelfshack/backend_secrets-OEhS1N:EMAILS_FROM_EMAIL::"
  },
  {
    name       = "FRONTEND_BASE_URL"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:dev/shelfshack/backend_secrets-OEhS1N:FRONTEND_BASE_URL::"
  },
  {
    name       = "STRIPE_SECRET_KEY"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:dev/shelfshack/backend_secrets-OEhS1N:STRIPE_SECRET_KEY::"
  }
]

# RDS inputs (do not commit real passwords; set TF_VAR_db_master_password via secrets/provider)
db_master_username  = "dbadmin_shelfshack"
# db_master_password is intentionally unset; provide it via TF_VAR_DB_MASTER_PASSWORD in CI/secrets.
db_allocated_storage = 20
db_engine_version    = "17.6"
db_multi_az          = false
db_backup_retention_days = 0
db_skip_final_snapshot   = true
db_deletion_protection   = false
db_apply_immediately     = true
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
opensearch_ec2_instance_type = "m7i-flex.large"  # 8GB RAM, 2 vCPU (BEST FREE TIER option!)
opensearch_ec2_java_heap_size = "2g"  # Optimal heap for m7i-flex.large (8GB RAM)

# WebSocket API Gateway and Lambda Configuration
websocket_stage_name = "development"
# Path to Lambda source file - relative path from envs/dev directory
# Lambda code is now part of the infra repo at: ../../lambda/websocket_proxy.py
websocket_lambda_source_file = "../../lambda/websocket_proxy.py"
# Path to Lambda requirements.txt - relative path from envs/dev directory
websocket_lambda_requirements_file = "../../lambda/requirements.txt"
# Optional: Override backend URL (defaults to ALB URL if available)
# websocket_backend_url = "https://api.yourdomain.com"
