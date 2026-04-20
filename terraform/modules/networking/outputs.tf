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

output "dev_database_subnet_ids" {
  description = "Dev database subnet IDs"
  value       = [module.vpc.database_subnets[0], module.vpc.database_subnets[1]]
}

output "prod_database_subnet_ids" {
  description = "Prod database subnet IDs"
  value       = [module.vpc.database_subnets[2], module.vpc.database_subnets[3]]
}

output "dev_database_subnet_group_name" {
  description = "Dev database subnet group name"
  value       = aws_db_subnet_group.dev.name
}

output "prod_database_subnet_group_name" {
  description = "Prod database subnet group name"
  value       = aws_db_subnet_group.prod.name
}

output "private_route_table_ids" {
  description = "Private route table IDs"
  value       = module.vpc.private_route_table_ids
}

output "public_route_table_ids" {
  description = "Public route table IDs"
  value       = module.vpc.public_route_table_ids
}

output "database_route_table_ids" {
  description = "Database route table IDs"
  value       = module.vpc.database_route_table_ids
}

output "nat_gateway_id" {
  description = "NAT Gateway ID (if enabled)"
  value       = var.nat_gateway_enabled ? module.vpc.nat_gateway_ids[0] : null
}

output "nat_instance_id" {
  description = "NAT Instance ID (if enabled)"
  value       = !var.nat_gateway_enabled ? aws_instance.nat[0].id : null
}

output "nat_instance_private_ip" {
  description = "Private IP of the NAT instance"
  value       = !var.nat_gateway_enabled ? aws_instance.nat[0].private_ip : null
}

output "nat_eip" {
  description = "Elastic IP of the NAT instance"
  value       = !var.nat_gateway_enabled ? aws_eip.nat[0].public_ip : null
}

output "nat_security_group_id" {
  description = "Security group ID for NAT instance"
  value       = !var.nat_gateway_enabled ? aws_security_group.nat[0].id : null
}

output "nat_instance_enabled" {
  description = "Whether NAT instance is enabled"
  value       = !var.nat_gateway_enabled
}

