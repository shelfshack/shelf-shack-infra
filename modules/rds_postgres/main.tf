locals {
  tags = merge(var.tags, {
    Module = "rds-postgres"
  })

  # Generate final snapshot identifier if skip_final_snapshot is false
  final_snapshot_identifier = var.skip_final_snapshot ? null : (
    var.final_snapshot_identifier != null ? var.final_snapshot_identifier : "${var.name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  )
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnets"
  subnet_ids = var.subnet_ids

  tags = merge(local.tags, {
    Name = "${var.name}-db-subnets"
  })

  lifecycle {
    # Force replacement when subnet IDs change, as AWS doesn't allow
    # modifying the VPC of an existing DB subnet group
    create_before_destroy = true
  }
}

resource "aws_security_group" "this" {
  name        = "${var.name}-db-sg"
  description = "Allow PostgreSQL access"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-db-sg"
  })
}

resource "aws_db_instance" "this" {
  identifier              = "${var.name}-postgres"
  engine                  = "postgres"
  engine_version          = var.engine_version
  instance_class          = var.instance_class
  allocated_storage       = var.allocated_storage
  db_name                 = var.db_name
  username                = var.master_username
  password                = var.master_password
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [aws_security_group.this.id]
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
    Name = "${var.name}-postgres"
  })
}
