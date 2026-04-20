variable "project_name" {
  description = "Project name"
  type        = string
  default     = "serenity"
}

variable "app" {
  description = "Application name for resource tagging"
  type        = string
  default     = "serenity"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.micro"

  validation {
    condition     = startswith(var.redis_node_type, "cache.")
    error_message = "Redis node type must be a valid ElastiCache node type starting with 'cache.'."
  }
}

variable "snapshot_retention_limit" {
  description = "Redis snapshot retention limit in days"
  type        = number
  default     = 1
}

variable "allowed_admin_cidrs" {
  description = "CIDR blocks allowed to access Redis directly (e.g. admin laptop IP)"
  type        = list(string)
  default     = []
}
