terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  # Map public subnets to AZs: index 0,1 → azs[0]; index 2,3 → azs[1]
  public_subnet_az_map = [
    var.azs[0], var.azs[0],
    var.azs[1], var.azs[1],
  ]
  private_subnet_az_map = [
    var.azs[0], var.azs[0],
    var.azs[1], var.azs[1],
  ]

  common_tags = merge(var.tags, {
    Name        = var.name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# ──────────────────────────────────────────────────────────────
# VPC
# ──────────────────────────────────────────────────────────────
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, { Name = "${var.name}-vpc" })
}

# ──────────────────────────────────────────────────────────────
# Internet Gateway
# ──────────────────────────────────────────────────────────────
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${var.name}-igw" })
}

# ──────────────────────────────────────────────────────────────
# Subnets — 4 public, 4 private
# ──────────────────────────────────────────────────────────────
resource "aws_subnet" "public" {
  count                   = 4
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.public_subnet_az_map[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.name}-public-${count.index + 1}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count             = 4
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.private_subnet_az_map[count.index]

  tags = merge(local.common_tags, {
    Name = "${var.name}-private-${count.index + 1}"
    Tier = "private"
  })
}

# ──────────────────────────────────────────────────────────────
# NAT Gateways — one per AZ for high availability
# ──────────────────────────────────────────────────────────────
resource "aws_eip" "nat" {
  count  = 2
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${var.name}-nat-eip-${count.index + 1}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count         = 2
  allocation_id = aws_eip.nat[count.index].id
  # Place each NAT GW in the first public subnet of each AZ (index 0 → az[0], index 2 → az[1])
  subnet_id = aws_subnet.public[count.index * 2].id

  tags       = merge(local.common_tags, { Name = "${var.name}-nat-${count.index + 1}" })
  depends_on = [aws_internet_gateway.this]

  timeouts {
    create = "20m"
    delete = "20m"
  }
}

# ──────────────────────────────────────────────────────────────
# Route Tables
# ──────────────────────────────────────────────────────────────

# Single public route table — all public subnets share a default route via IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, { Name = "${var.name}-rt-public" })
}

resource "aws_route_table_association" "public" {
  count          = 4
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Two private route tables — one per AZ, each routing through its own NAT GW
resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }

  tags = merge(local.common_tags, { Name = "${var.name}-rt-private-az${count.index + 1}" })
}

# Private subnets 0,1 → rt[0] (az1); subnets 2,3 → rt[1] (az2)
resource "aws_route_table_association" "private" {
  count          = 4
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[floor(count.index / 2)].id
}

# ──────────────────────────────────────────────────────────────
# Security Group for VPC Interface Endpoints (SSM)
# ──────────────────────────────────────────────────────────────
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.name}-vpc-endpoints"
  description = "Allow HTTPS from within VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.name}-sg-vpc-endpoints" })
}

# ──────────────────────────────────────────────────────────────
# S3 Gateway Endpoint (free, no security group required)
# ──────────────────────────────────────────────────────────────
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = merge(local.common_tags, { Name = "${var.name}-endpoint-s3" })
}

# ──────────────────────────────────────────────────────────────
# SSM Interface Endpoints (required for SSM Session Manager
# to work without internet access from private subnets)
# ──────────────────────────────────────────────────────────────
locals {
  ssm_services = ["ssm", "ssmmessages", "ec2messages"]
}

resource "aws_vpc_endpoint" "ssm" {
  for_each = toset(local.ssm_services)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.key}"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  subnet_ids          = [aws_subnet.private[0].id, aws_subnet.private[2].id] # one per AZ
  private_dns_enabled = true

  tags = merge(local.common_tags, { Name = "${var.name}-endpoint-${each.key}" })

  timeouts {
    create = "20m"
    delete = "20m"
  }
}

data "aws_region" "current" {}
