output "vpc_id" {
  description = "ID of the VPC (created or existing)."
  value       = local.effective_vpc_id
}

output "public_subnet_ids" {
  description = "IDs of public subnets."
  value       = local.should_create ? [for s in aws_subnet.public : s.id] : (
    length(data.aws_subnets.existing_public) > 0 ? data.aws_subnets.existing_public[0].ids : []
  )
}

output "private_subnet_ids" {
  description = "IDs of private subnets."
  value       = local.should_create ? [for s in aws_subnet.private : s.id] : (
    length(data.aws_subnets.existing_private) > 0 ? data.aws_subnets.existing_private[0].ids : []
  )
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
