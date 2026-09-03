output "vpc_id" {
  description = "ID da VPC."
  value       = module.networking.vpc_id
}

output "vpc_cidr_block" {
  description = "Bloco CIDR da VPC."
  value       = module.networking.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs das subnets públicas."
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas."
  value       = module.networking.private_subnet_ids
}

output "internet_gateway_id" {
  description = "ID do Internet Gateway."
  value       = module.networking.internet_gateway_id
}

output "nat_gateway_ids" {
  description = "IDs dos NAT Gateways."
  value       = module.networking.nat_gateway_ids
}

output "availability_zones" {
  description = "AZs efetivamente utilizadas."
  value       = module.networking.availability_zones
}
