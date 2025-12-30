output "vpc_id" {
  description = "ID of the VPC (created or existing)."
  value       = local.effective_vpc_id
}

output "public_subnet_ids" {
  description = "IDs of public subnets."
  value       = local.effective_public_subnet_ids
  
  # Precondition to ensure we never return empty subnets
  precondition {
    condition     = length(local.effective_public_subnet_ids) > 0
    error_message = "No public subnets found. Ensure subnets exist in VPC with Tier=public tag, or set create_if_not_exists=true to create them."
  }
}

output "private_subnet_ids" {
  description = "IDs of private subnets."
  value       = local.effective_private_subnet_ids
  
  # Precondition to ensure we never return empty subnets
  precondition {
    condition     = length(local.effective_private_subnet_ids) > 0
    error_message = "No private subnets found. Ensure subnets exist in VPC with Tier=private tag, or set create_if_not_exists=true to create them."
  }
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = local.should_create ? (
    length(aws_vpc.this) > 0 ? aws_vpc.this[0].cidr_block : ""
  ) : (
    length(data.aws_vpc.existing) > 0 ? data.aws_vpc.existing[0].cidr_block : ""
  )
}

output "vpc_created" {
  description = "Whether the VPC was created by this module (false if it already existed)."
  value       = local.should_create
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway."
  value       = local.effective_igw_id
}
