# RDS PostgreSQL Module
# Implements "create if not exists" pattern for resilience
# Handles cases where resources exist in AWS but not in Terraform state

locals {
  tags = merge(var.tags, {
    Module = "rds-postgres"
  })

  # Generate final snapshot identifier if skip_final_snapshot is false
  final_snapshot_identifier = var.skip_final_snapshot ? null : (
    var.final_snapshot_identifier != null ? var.final_snapshot_identifier : "${var.name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  )
  
  subnet_group_name = "${var.name}-db-subnets"
  security_group_name = "${var.name}-db-sg"
  db_identifier = "${var.name}-postgres"
}

# ============================================================================
# CHECK IF RESOURCES EXIST (for resilience)
# ============================================================================

# Check if DB subnet group exists
data "external" "check_subnet_group" {
  count = var.create_if_not_exists ? 1 : 0
  
  program = ["bash", "-c", <<-EOT
    if aws rds describe-db-subnet-groups --db-subnet-group-name "${local.subnet_group_name}" --region "${var.aws_region}" >/dev/null 2>&1; then
      echo "{\"exists\": \"true\"}"
    else
      echo "{\"exists\": \"false\"}"
    fi
  EOT
  ]
}

# Check if security group exists
data "external" "check_security_group" {
  count = var.create_if_not_exists ? 1 : 0
  
  program = ["bash", "-c", <<-EOT
    SG_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${var.vpc_id}" "Name=group-name,Values=${local.security_group_name}" --region "${var.aws_region}" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
    if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
      echo "{\"exists\": \"true\", \"security_group_id\": \"$SG_ID\"}"
    else
      echo "{\"exists\": \"false\", \"security_group_id\": \"\"}"
    fi
  EOT
  ]
}

# Check if RDS instance exists
data "external" "check_db_instance" {
  count = var.create_if_not_exists ? 1 : 0
  
  program = ["bash", "-c", <<-EOT
    DB_INFO=$(aws rds describe-db-instances --db-instance-identifier "${local.db_identifier}" --region "${var.aws_region}" --query 'DBInstances[0].[Endpoint.Address,Endpoint.Port,DBInstanceStatus]' --output text 2>/dev/null)
    if [ -n "$DB_INFO" ] && [ "$DB_INFO" != "None" ]; then
      ENDPOINT=$(echo "$DB_INFO" | cut -f1)
      PORT=$(echo "$DB_INFO" | cut -f2)
      STATUS=$(echo "$DB_INFO" | cut -f3)
      echo "{\"exists\": \"true\", \"endpoint\": \"$ENDPOINT\", \"port\": \"$PORT\", \"status\": \"$STATUS\"}"
    else
      echo "{\"exists\": \"false\", \"endpoint\": \"\", \"port\": \"\", \"status\": \"\"}"
    fi
  EOT
  ]
}

# Determine what to create
locals {
  subnet_group_exists = var.create_if_not_exists ? (
    try(data.external.check_subnet_group[0].result.exists, "false") == "true"
  ) : false
  
  security_group_exists = var.create_if_not_exists ? (
    try(data.external.check_security_group[0].result.exists, "false") == "true"
  ) : false
  
  existing_security_group_id = var.create_if_not_exists ? (
    try(data.external.check_security_group[0].result.security_group_id, "")
  ) : ""
  
  db_instance_exists = var.create_if_not_exists ? (
    try(data.external.check_db_instance[0].result.exists, "false") == "true"
  ) : false
  
  should_create_subnet_group = !local.subnet_group_exists
  should_create_security_group = !local.security_group_exists
  should_create_db_instance = !local.db_instance_exists
}

# ============================================================================
# CREATE RESOURCES (only if they don't exist)
# ============================================================================

resource "aws_db_subnet_group" "this" {
  count      = local.should_create_subnet_group ? 1 : 0
  name       = local.subnet_group_name
  subnet_ids = var.subnet_ids

  tags = merge(local.tags, {
    Name = local.subnet_group_name
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "this" {
  # Always create the security group resource - if it exists, Terraform will handle it
  count       = 1
  name        = local.security_group_name
  description = "Allow PostgreSQL access"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = local.security_group_name
  })
}

# Effective security group ID - always use the managed resource
locals {
  effective_security_group_id = length(aws_security_group.this) > 0 ? aws_security_group.this[0].id : ""
}

resource "aws_db_instance" "this" {
  count                   = local.should_create_db_instance ? 1 : 0
  identifier              = local.db_identifier
  engine                  = "postgres"
  engine_version          = var.engine_version
  instance_class          = var.instance_class
  allocated_storage       = var.allocated_storage
  db_name                 = var.db_name
  username                = var.master_username
  password                = var.master_password
  db_subnet_group_name    = local.should_create_subnet_group ? aws_db_subnet_group.this[0].name : local.subnet_group_name
  vpc_security_group_ids  = [local.effective_security_group_id]
  multi_az                = var.multi_az
  publicly_accessible     = var.publicly_accessible
  storage_type            = "gp3"
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  skip_final_snapshot     = var.skip_final_snapshot
  final_snapshot_identifier = local.final_snapshot_identifier
  deletion_protection     = var.deletion_protection
  apply_immediately       = var.apply_immediately
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  tags = merge(local.tags, {
    Name = local.db_identifier
  })
}

# ============================================================================
# OUTPUT LOCALS (normalize created vs existing)
# ============================================================================

locals {
  # Endpoint - use created or existing
  db_endpoint = local.should_create_db_instance ? (
    length(aws_db_instance.this) > 0 ? aws_db_instance.this[0].endpoint : ""
  ) : (
    try(data.external.check_db_instance[0].result.endpoint, "")
  )
  
  db_port = local.should_create_db_instance ? (
    length(aws_db_instance.this) > 0 ? aws_db_instance.this[0].port : 5432
  ) : (
    try(tonumber(data.external.check_db_instance[0].result.port), 5432)
  )
  
  db_address = local.should_create_db_instance ? (
    length(aws_db_instance.this) > 0 ? aws_db_instance.this[0].address : ""
  ) : (
    try(data.external.check_db_instance[0].result.endpoint, "")
  )
}
