variable "enabled" {
  description = "Enable NAT instance (set to false to use NAT Gateway instead)"
  type        = bool
  default     = false
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID for NAT instance"
  type        = string
}

variable "private_subnets_cidr" {
  description = "CIDR blocks of private subnets that will use NAT"
  type        = list(string)
}

variable "private_cidr" {
  description = "VPC private CIDR block for NAT routing"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_route_table_ids" {
  description = "Route table IDs for private subnets"
  type        = list(string)
  default     = []
}

variable "instance_type" {
  description = "Instance type for NAT (t4g.nano recommended for cost)"
  type        = string
  default     = "t4g.nano"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
