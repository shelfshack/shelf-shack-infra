aws_region   = "us-east-1"
project      = "rentify"
environment  = "dev"

availability_zones = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
enable_bastion_host  = true
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
  NODE_ENV = "production"
  DB_MANAGE_COMMAND = "--create --bootstrap"
  DB_BOOTSTRAP = "true"
}

force_new_deployment = true

app_secrets = [
  {
    name       = "DATABASE_URL"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:rentify/db_url-9ixzM1:DATABASE_URL::"
  },
  {
    name       = "GOOGLE_CLIENT_ID"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:google_api_client_id-aZhag9:GOOGLE_CLIENT_ID::"
  },
  {
    name       = "SMTP_SERVER"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:smtp_secret-3u8sxy:SMTP_SERVER::"
  },
  {
    name       = "SMTP_PORT"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:smtp_secret-3u8sxy:SMTP_PORT::"
  },
  {
    name       = "SMTP_USERNAME"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:smtp_secret-3u8sxy:SMTP_USERNAME::"
  },
  {
    name       = "SMTP_PASSWORD"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:smtp_secret-3u8sxy:SMTP_PASSWORD::"
  },
  {
    name       = "EMAILS_FROM_EMAIL"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:smtp_secret-3u8sxy:EMAILS_FROM_EMAIL::"
  },
  {
    name       = "FRONTEND_BASE_URL"
    value_from = "arn:aws:secretsmanager:us-east-1:506852294788:secret:smtp_secret-3u8sxy:FRONTEND_BASE_URL::"
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
  "arn:aws:iam::506852294788:role/RentDeployRole"
]

# Optional: Add your IP for Kibana access (leave empty if not needed)
# Example: opensearch_allowed_cidr_blocks = ["1.2.3.4/32"]
opensearch_allowed_cidr_blocks = []

# Set to false if the OpenSearch service-linked role already exists in your account
# (The role can only be created once per AWS account and requires special IAM permissions)
opensearch_create_service_linked_role = false
