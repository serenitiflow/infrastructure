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
  description = "Environment name (dev, staging, prod, shared)"
  type        = string
  default     = "shared"

  validation {
    condition     = can(regex("^(dev|staging|prod|shared)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod, shared."
  }
}

variable "environments" {
  description = "List of environments to create DB subnets for"
  type        = list(string)
  default     = ["dev", "prod"]
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "nat_gateway_enabled" {
  description = "Use NAT Gateway (true) or NAT Instance (false)"
  type        = bool
  default     = false
}

variable "nat_instance_type" {
  description = "Instance type for NAT (if not using Gateway)"
  type        = string
  default     = "t4g.nano"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}
