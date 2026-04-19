output "nat_instance_id" {
  description = "ID of the NAT instance"
  value       = var.enabled ? aws_instance.nat[0].id : null
}

output "nat_instance_private_ip" {
  description = "Private IP of the NAT instance"
  value       = var.enabled ? aws_instance.nat[0].private_ip : null
}

output "nat_eip" {
  description = "Elastic IP of the NAT instance"
  value       = var.enabled ? aws_eip.nat[0].public_ip : null
}

output "nat_security_group_id" {
  description = "Security group ID for NAT instance"
  value       = var.enabled ? aws_security_group.nat[0].id : null
}

output "nat_enabled" {
  description = "Whether NAT instance is enabled"
  value       = var.enabled
}
