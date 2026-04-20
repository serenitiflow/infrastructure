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
  default     = "us-east-1"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.35"

  validation {
    condition     = can(regex("^1\\.(3[0-9]|[4-9][0-9])$", var.kubernetes_version))
    error_message = "Kubernetes version must be 1.30 or higher."
  }
}

variable "cluster_endpoint_public_access" {
  description = "Enable public EKS API endpoint (disable for prod security)"
  type        = bool
  default     = false
}

variable "allowed_public_cidrs" {
  description = "Allowed CIDRs for public EKS endpoint (required if public access enabled)"
  type        = list(string)
  default     = []
}

variable "capacity_type" {
  description = "Capacity type for EKS nodes (SPOT or ON_DEMAND)"
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.capacity_type)
    error_message = "Capacity type must be SPOT or ON_DEMAND."
  }
}

variable "node_instance_types" {
  description = "Instance types for EKS nodes"
  type        = list(string)
  default     = ["t4g.medium", "t3a.medium", "t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of EKS nodes"
  type        = number
  default     = 1

  validation {
    condition     = var.node_desired_size >= 0
    error_message = "Desired node size must be non-negative."
  }
}

variable "node_min_size" {
  description = "Minimum number of EKS nodes"
  type        = number
  default     = 1

  validation {
    condition     = var.node_min_size >= 0
    error_message = "Minimum node size must be non-negative."
  }
}

variable "node_max_size" {
  description = "Maximum number of EKS nodes"
  type        = number
  default     = 3

  validation {
    condition     = var.node_max_size >= 1
    error_message = "Maximum node size must be at least 1."
  }
}

variable "cluster_enabled_log_types" {
  description = "EKS control plane log types to enable (empty list disables CloudWatch)"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cloudwatch_retention_days" {
  description = "CloudWatch log group retention in days (cost optimization)"
  type        = number
  default     = 7

  validation {
    condition     = var.cloudwatch_retention_days >= 1
    error_message = "CloudWatch retention must be at least 1 day."
  }
}

variable "access_entries" {
  description = "EKS access entries for IAM principals. See https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html"
  type        = any
  default     = {}
}

