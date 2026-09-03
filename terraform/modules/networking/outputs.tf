output "vpc_id" {
  description = "ID da VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "Bloco CIDR da VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs das subnets públicas."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas."
  value       = aws_subnet.private[*].id
}

output "public_subnet_cidrs" {
  description = "Blocos CIDR das subnets públicas."
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "Blocos CIDR das subnets privadas."
  value       = aws_subnet.private[*].cidr_block
}

output "internet_gateway_id" {
  description = "ID do Internet Gateway."
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_ids" {
  description = "IDs dos NAT Gateways (vazio se desabilitado)."
  value       = aws_nat_gateway.this[*].id
}

output "nat_public_ips" {
  description = "Elastic IPs associados aos NAT Gateways."
  value       = aws_eip.nat[*].public_ip
}

output "public_route_table_id" {
  description = "ID da route table pública."
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "IDs das route tables privadas."
  value       = aws_route_table.private[*].id
}

output "availability_zones" {
  description = "AZs utilizadas pelas subnets."
  value       = var.availability_zones
}
