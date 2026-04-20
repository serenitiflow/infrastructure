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

variable "db_username" {
  description = "Database master username"
  type        = string
}

variable "aurora_instance_class" {
  description = "Aurora instance class"
  type        = string
  default     = "db.serverless"
}

variable "aurora_min_capacity" {
  description = "Minimum ACUs for Aurora Serverless v2"
  type        = number
  default     = 0.5

  validation {
    condition     = var.aurora_min_capacity >= 0.5
    error_message = "Aurora min capacity must be at least 0.5 ACUs."
  }
}

variable "aurora_max_capacity" {
  description = "Maximum ACUs for Aurora Serverless v2"
  type        = number
  default     = 2

  validation {
    condition     = var.aurora_max_capacity >= 0.5
    error_message = "Aurora max capacity must be at least 0.5 ACUs."
  }
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

variable "aurora_scheduler_enabled" {
  description = "Enable Aurora scheduled stop/start"
  type        = bool
  default     = true
}

variable "backup_retention_period" {
  description = "Aurora backup retention period in days"
  type        = number
  default     = 3

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 1 and 35 days."
  }
}

variable "snapshot_retention_limit" {
  description = "Redis snapshot retention limit in days"
  type        = number
  default     = 1
}

variable "allowed_admin_cidrs" {
  description = "CIDR blocks allowed to access databases directly (e.g. admin laptop IP)"
  type        = list(string)
  default     = []
}
