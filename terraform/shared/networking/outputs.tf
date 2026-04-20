output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.networking.vpc_cidr
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.networking.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.networking.public_subnet_ids
}

output "database_subnet_ids" {
  description = "Database subnet IDs"
  value       = module.networking.database_subnet_ids
}

output "private_route_table_ids" {
  description = "Private route table IDs"
  value       = module.networking.private_route_table_ids
}

output "public_route_table_ids" {
  description = "Public route table IDs"
  value       = module.networking.public_route_table_ids
}

output "nat_gateway_id" {
  description = "NAT Gateway ID (if enabled)"
  value       = module.networking.nat_gateway_id
}

output "nat_instance_id" {
  description = "NAT Instance ID (if enabled)"
  value       = module.networking.nat_instance_id
}
