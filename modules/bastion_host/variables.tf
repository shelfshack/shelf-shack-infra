variable "enabled" {
  description = "Whether to provision the bastion host."
  type        = bool
  default     = false
}

variable "name" {
  description = "Base name for tagging resources."
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID where the bastion instance runs."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for security group attachment."
  type        = string
}

variable "instance_type" {
  description = "Instance type for the bastion."
  type        = string
  default     = "t3.micro"
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}

variable "allow_ssh_cidr_blocks" {
  description = "Optional list of CIDR blocks allowed to SSH directly (leave empty to rely on SSM)."
  type        = list(string)
  default     = []
}
