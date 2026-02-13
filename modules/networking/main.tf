# Networking Module
# Supports "create if not exists" pattern to prevent duplicate VPCs when state is lost

locals {
  tags = merge(var.tags, {
    Module = "networking"
  })

  ssm_endpoint_services = [
    "ssm",
    "ssmmessages",
    "ec2messages"
  ]
  
  secretsmanager_services = [
    "secretsmanager"
  ]
  
  vpc_name = "${var.name}-vpc"
}

data "aws_region" "current" {}

# Check if VPC already exists using AWS CLI
# This is safer than a data source because it doesn't fail if VPC doesn't exist
data "external" "check_vpc_exists" {
  count = var.create_if_not_exists ? 1 : 0
  
  program = ["bash", "-c", <<-EOT
    VPC_INFO=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${local.vpc_name}" --region "${var.aws_region}" --query 'Vpcs[0].[VpcId,CidrBlock]' --output text 2>/dev/null)
    if [ -n "$VPC_INFO" ] && [ "$VPC_INFO" != "None" ]; then
      VPC_ID=$(echo "$VPC_INFO" | cut -f1)
      VPC_CIDR=$(echo "$VPC_INFO" | cut -f2)
      if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
        echo "{\"exists\": \"true\", \"vpc_id\": \"$VPC_ID\", \"cidr_block\": \"$VPC_CIDR\"}"
      else
        echo "{\"exists\": \"false\", \"vpc_id\": \"\", \"cidr_block\": \"\"}"
      fi
    else
      echo "{\"exists\": \"false\", \"vpc_id\": \"\", \"cidr_block\": \"\"}"
    fi
  EOT
  ]
}

# Determine if we need to create resources or use existing
locals {
  vpc_exists = var.create_if_not_exists ? (
    try(data.external.check_vpc_exists[0].result.exists, "false") == "true"
  ) : false
  
  existing_vpc_id = local.vpc_exists ? try(data.external.check_vpc_exists[0].result.vpc_id, "") : ""
  
  should_create = !local.vpc_exists

  igw_exists = local.vpc_exists ? (try(data.external.check_igw_exists[0].result.exists, "false") == "true") : false
  existing_igw_id = local.igw_exists ? try(data.external.check_igw_exists[0].result.igw_id, "") : ""
  should_create_igw_for_existing_vpc = local.vpc_exists && !local.igw_exists

  existing_public_subnet_ids  = local.vpc_exists ? try(data.aws_subnets.existing_public[0].ids, []) : []
  existing_private_subnet_ids = local.vpc_exists ? try(data.aws_subnets.existing_private[0].ids, []) : []

  should_create_public_subnets  = !local.vpc_exists || length(local.existing_public_subnet_ids) == 0
  should_create_private_subnets = !local.vpc_exists || length(local.existing_private_subnet_ids) == 0
}

# Use data source to get existing VPC details if it exists
data "aws_vpc" "existing" {
  count = local.vpc_exists ? 1 : 0
  id    = local.existing_vpc_id
}

data "aws_subnets" "existing_public" {
  count = local.vpc_exists ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [local.existing_vpc_id]
  }
  
  filter {
    name   = "tag:Tier"
    values = ["public"]
  }
}

data "aws_subnets" "existing_private" {
  count = local.vpc_exists ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [local.existing_vpc_id]
  }
  
  filter {
    name   = "tag:Tier"
    values = ["private"]
  }
}

# Check if IGW already exists for the VPC (CLI to avoid hard failure)
data "external" "check_igw_exists" {
  count = local.vpc_exists ? 1 : 0

  program = ["bash", "-c", <<-EOT
    IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${local.existing_vpc_id}" --region "${var.aws_region}" --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null)
    if [ -n "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
      echo "{\"exists\": \"true\", \"igw_id\": \"$IGW_ID\"}"
    else
      echo "{\"exists\": \"false\", \"igw_id\": \"\"}"
    fi
  EOT
  ]
}

# ============================================================================
# CREATE NEW RESOURCES (only if VPC doesn't exist)
# ============================================================================

resource "aws_vpc" "this" {
  count = local.should_create ? 1 : 0
  
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  lifecycle {
    # Prevent accidental destruction of VPC
    prevent_destroy = false  # Set to true in production for extra safety

    # Ignore changes to tags to prevent replacement
    ignore_changes = [tags]

    precondition {
      condition     = length(var.availability_zones) == length(var.public_subnet_cidrs) && length(var.availability_zones) == length(var.private_subnet_cidrs)
      error_message = "availability_zones must match the number of public and private subnet CIDRs."
    }
  }

  tags = merge(local.tags, {
    Name = local.vpc_name
  })
}

resource "aws_internet_gateway" "this" {
  # Create IGW if creating VPC, or if VPC exists but no IGW is attached
  count  = local.should_create || local.should_create_igw_for_existing_vpc ? 1 : 0
  vpc_id = local.should_create ? aws_vpc.this[0].id : local.existing_vpc_id

  tags = merge(local.tags, {
    Name = "${var.name}-igw"
  })
}

locals {
  az_count = length(var.availability_zones)
  
  # Use existing or created VPC ID
  effective_vpc_id = local.should_create ? (
    length(aws_vpc.this) > 0 ? aws_vpc.this[0].id : ""
  ) : local.existing_vpc_id
  
  # Use existing or created IGW ID
  effective_igw_id = local.should_create ? (
    length(aws_internet_gateway.this) > 0 ? aws_internet_gateway.this[0].id : ""
  ) : (
    local.igw_exists ? local.existing_igw_id : (
      length(aws_internet_gateway.this) > 0 ? aws_internet_gateway.this[0].id : ""
    )
  )

  effective_public_subnet_ids = local.should_create_public_subnets ? [for s in aws_subnet.public : s.id] : local.existing_public_subnet_ids
  effective_private_subnet_ids = local.should_create_private_subnets ? [for s in aws_subnet.private : s.id] : local.existing_private_subnet_ids

  have_igw = length(local.effective_igw_id) > 0
}

resource "aws_subnet" "public" {
  for_each = local.should_create_public_subnets ? {
    for idx, cidr in var.public_subnet_cidrs :
    idx => {
      cidr = cidr
      az   = var.availability_zones[idx]
    }
  } : {}

  vpc_id                  = local.effective_vpc_id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "${var.name}-public-${each.key}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  for_each = local.should_create_private_subnets ? {
    for idx, cidr in var.private_subnet_cidrs :
    idx => {
      cidr = cidr
      az   = var.availability_zones[idx]
    }
  } : {}

  vpc_id                  = local.effective_vpc_id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${var.name}-private-${each.key}"
    Tier = "private"
  })
}

resource "aws_eip" "nat" {
  count      = local.should_create && var.enable_nat_gateway ? 1 : 0
  domain     = "vpc"
  depends_on = [aws_internet_gateway.this]

  tags = merge(local.tags, {
    Name = "${var.name}-nat-eip"
  })
}

resource "aws_nat_gateway" "this" {
  count         = local.should_create && var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = values(aws_subnet.public)[0].id

  tags = merge(local.tags, {
    Name = "${var.name}-nat"
  })
}

resource "aws_route_table" "public" {
  count  = (local.should_create || local.should_create_public_subnets) ? 1 : 0
  vpc_id = local.effective_vpc_id

  tags = merge(local.tags, {
    Name = "${var.name}-public-rt"
  })
}

resource "aws_route" "public_internet_access" {
  # Create route only when:
  # 1. Creating new VPC (IGW will be created via aws_internet_gateway.this[0])
  # 2. IGW exists for existing VPC (use existing_igw_id)
  # 3. Creating IGW for existing VPC (use aws_internet_gateway.this[0])
  count = (local.should_create || local.igw_exists || local.should_create_igw_for_existing_vpc) && (local.should_create || local.should_create_public_subnets) ? 1 : 0
  
  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  
  # Use IGW ID based on scenario:
  # - If creating new VPC or IGW for existing: use the created IGW
  # - If IGW exists: use existing IGW ID
  gateway_id = (local.should_create || local.should_create_igw_for_existing_vpc) ? (
    length(aws_internet_gateway.this) > 0 ? aws_internet_gateway.this[0].id : local.existing_igw_id
  ) : local.existing_igw_id

  # Wait for IGW to be created/attached before creating route
  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table_association" "public" {
  for_each = local.should_create_public_subnets ? {
    for idx, cidr in var.public_subnet_cidrs :
    tostring(idx) => cidr
  } : {}
  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table" "private" {
  count  = (local.should_create || local.should_create_private_subnets) ? 1 : 0
  vpc_id = local.effective_vpc_id

  tags = merge(local.tags, {
    Name = "${var.name}-private-rt"
  })
}

resource "aws_route" "private_outbound" {
  count                  = length(aws_nat_gateway.this) > 0 ? 1 : 0
  route_table_id         = aws_route_table.private[0].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "private" {
  for_each = local.should_create_private_subnets ? {
    for idx, cidr in var.private_subnet_cidrs :
    tostring(idx) => cidr
  } : {}
  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[0].id
}

# ============================================================================
# SSM ENDPOINTS (create only if VPC is being created)
# ============================================================================

resource "aws_security_group" "ssm_endpoints" {
  count = local.should_create && var.enable_ssm_endpoints ? 1 : 0

  name        = "${var.name}-ssm-endpoints"
  description = "Allow HTTPS access to SSM interface endpoints"
  vpc_id      = local.effective_vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-ssm-endpoints"
  })
}

resource "aws_vpc_endpoint" "ssm" {
  for_each            = local.should_create && var.enable_ssm_endpoints ? { for svc in local.ssm_endpoint_services : svc => svc } : {}
  vpc_id              = local.effective_vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.ssm_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.name}-${each.value}-endpoint"
  })
}

# Secrets Manager endpoint (optional, for private access to secrets)
resource "aws_vpc_endpoint" "secretsmanager" {
  for_each            = local.should_create && var.enable_secretsmanager_endpoint ? { for svc in local.secretsmanager_services : svc => svc } : {}
  vpc_id              = local.effective_vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.ssm_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.name}-${each.value}-endpoint"
  })
}
