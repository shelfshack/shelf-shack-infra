variable "bucket_name" {
  description = "Name of the S3 bucket for uploads"
  type        = string
}

variable "item_prefix" {
  description = "Prefix for item images (e.g., 'item_images')"
  type        = string
  default     = "item_images"
}

variable "profile_prefix" {
  description = "Prefix for profile photos (e.g., 'profile_photos')"
  type        = string
  default     = "profile_photos"
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = false
}

variable "lifecycle_days" {
  description = "Number of days to keep old versions (0 to disable lifecycle)"
  type        = number
  default     = 0
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS"
  type        = list(string)
  default     = ["*"]
}

variable "tags" {
  description = "Tags to apply to the S3 bucket"
  type        = map(string)
  default     = {}
}

variable "ecs_task_role_arn" {
  description = "ARN of the ECS task role to grant upload permissions (optional)"
  type        = string
  default     = null
}
