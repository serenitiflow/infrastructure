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

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.35"
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
  default     = "ON_DEMAND"
}

variable "node_instance_types" {
  description = "Instance types for EKS nodes (must be same architecture - ARM64 t4g/m6g/c6g/r6g OR x86_64 t3/t3a/m5/c5)"
  type        = list(string)
  default     = ["t3a.medium", "t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of EKS nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of EKS nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of EKS nodes"
  type        = number
  default     = 5
}

variable "cluster_enabled_log_types" {
  description = "EKS control plane log types to enable (empty list disables CloudWatch)"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cloudwatch_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 30
}

variable "access_entries" {
  description = "EKS access entries for IAM principals"
  type        = any
  default     = {}
}

variable "enable_kubernetes_dashboard" {
  description = "Enable Kubernetes Dashboard Helm release"
  type        = bool
  default     = false
}
