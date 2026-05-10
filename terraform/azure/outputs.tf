output "vnet_id" {
  value = azurerm_virtual_network.main.id
}

output "private_subnet_ids" {
  value = [azurerm_subnet.private_app.id, azurerm_subnet.private_data.id]
}

output "public_subnet_id" {
  value = azurerm_subnet.public.id
}

output "firewall_public_ip" {
  value = azurerm_public_ip.firewall.ip_address
}

output "app_nsg_id" {
  value = azurerm_network_security_group.private_app.id
}
