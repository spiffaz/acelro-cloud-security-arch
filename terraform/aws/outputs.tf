output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "nat_gateway_ids" {
  value = aws_nat_gateway.main[*].id
}

output "app_sg_id" {
  value = aws_security_group.app.id
}

output "bastion_sg_id" {
  value = aws_security_group.bastion.id
}

output "data_sg_id" {
  value = aws_security_group.data.id
}
