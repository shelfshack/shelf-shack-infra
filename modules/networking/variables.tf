variable "name" {
  description = "Base name used for tagging networking resources."
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "availability_zones" {
  description = "List of AZs to spread subnets across. Must match subnet CIDR list lengths."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "List of CIDRs for public subnets."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of CIDRs for private subnets."
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Whether to create a single shared NAT Gateway for private subnets."
  type        = bool
  default     = true
}

variable "enable_ssm_endpoints" {
  description = "Create VPC interface endpoints for Systems Manager services (required for ECS Exec in private subnets)."
  type        = bool
  default     = true
}

variable "enable_secretsmanager_endpoint" {
  description = "Create VPC interface endpoint for Secrets Manager to allow private access to secrets."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Optional tags applied to networking resources."
  type        = map(string)
  default     = {}
}

variable "create_if_not_exists" {
  description = "If true, check if VPC with the same name exists before creating. If it exists, use the existing VPC instead of creating a new one. This prevents duplicate VPC creation when Terraform state is lost."
  type        = bool
  default     = true
}

variable "aws_region" {
  description = "AWS region for the VPC. Required for existence check when create_if_not_exists is true."
  type        = string
  default     = "us-east-1"
}
