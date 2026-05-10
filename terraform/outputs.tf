# AWS outputs
output "aws_vpc_id" {
  description = "AWS VPC ID"
  value       = module.aws_network.vpc_id
}

output "aws_private_subnet_ids" {
  description = "AWS private subnet IDs"
  value       = module.aws_network.private_subnet_ids
}

output "aws_public_subnet_ids" {
  description = "AWS public subnet IDs"
  value       = module.aws_network.public_subnet_ids
}

output "aws_nat_gateway_ids" {
  description = "AWS NAT gateway IDs"
  value       = module.aws_network.nat_gateway_ids
}

output "aws_app_sg_id" {
  description = "Security group ID for application tier"
  value       = module.aws_network.app_sg_id
}

output "aws_bastion_sg_id" {
  description = "Security group ID for bastion host"
  value       = module.aws_network.bastion_sg_id
}

# Azure outputs
output "azure_vnet_id" {
  description = "Azure VNet ID"
  value       = module.azure_network.vnet_id
}

output "azure_private_subnet_ids" {
  description = "Azure private subnet IDs"
  value       = module.azure_network.private_subnet_ids
}

output "azure_public_subnet_id" {
  description = "Azure public subnet ID"
  value       = module.azure_network.public_subnet_id
}

output "azure_firewall_public_ip" {
  description = "Azure Firewall public IP"
  value       = module.azure_network.firewall_public_ip
}
