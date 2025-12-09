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

variable "tags" {
  description = "Optional tags applied to networking resources."
  type        = map(string)
  default     = {}
}
