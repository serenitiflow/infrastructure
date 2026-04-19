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
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "nat_gateway_enabled" {
  description = "Use NAT Gateway (true) or NAT Instance (false)"
  type        = bool
  default     = true
}

variable "nat_instance_type" {
  description = "Instance type for NAT (if not using Gateway)"
  type        = string
  default     = "t4g.small"
}
