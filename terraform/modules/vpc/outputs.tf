output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the 4 public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the 4 private subnets"
  value       = aws_subnet.private[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways (one per AZ)"
  value       = aws_nat_gateway.this[*].id
}

output "private_route_table_ids" {
  description = "IDs of the private route tables (one per AZ)"
  value       = aws_route_table.private[*].id
}

output "vpc_endpoint_s3_id" {
  description = "ID of the S3 Gateway endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "vpc_endpoint_ssm_ids" {
  description = "Map of SSM interface endpoint IDs"
  value       = { for k, v in aws_vpc_endpoint.ssm : k => v.id }
}
