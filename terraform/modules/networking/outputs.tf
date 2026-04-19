# Outputs for direct consumption
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

output "database_subnet_ids" {
  description = "Database subnet IDs"
  value       = module.vpc.database_subnets
}

output "database_subnet_group_name" {
  description = "Database subnet group name"
  value       = module.vpc.database_subnet_group_name
}

output "private_route_table_ids" {
  description = "Private route table IDs"
  value       = module.vpc.private_route_table_ids
}

output "public_route_table_ids" {
  description = "Public route table IDs"
  value       = module.vpc.public_route_table_ids
}

output "nat_gateway_id" {
  description = "NAT Gateway ID (if enabled)"
  value       = var.nat_gateway_enabled ? module.vpc.nat_gateway_ids[0] : null
}

output "nat_instance_id" {
  description = "NAT Instance ID (if enabled)"
  value       = module.nat_instance.nat_instance_id
}

