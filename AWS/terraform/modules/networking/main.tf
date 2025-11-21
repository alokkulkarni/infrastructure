# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.environment_tag}-vpc"
    EnvironmentTag = var.environment_tag
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.environment_tag}-igw"
    EnvironmentTag = var.environment_tag
  }
}

# Public Subnet 1
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.environment_tag}-public-subnet-1"
    Type = "Public"
    EnvironmentTag = var.environment_tag
  }
}

# Public Subnet 2 (for ALB multi-AZ requirement)
resource "aws_subnet" "public_2" {
  count                   = var.public_subnet_2_cidr != "" && var.availability_zone_2 != "" ? 1 : 0
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_2_cidr
  availability_zone       = var.availability_zone_2
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.environment_tag}-public-subnet-2"
    Type = "Public"
    EnvironmentTag = var.environment_tag
  }
}

# Private Subnet
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.environment_tag}-private-subnet"
    Type = "Private"
    EnvironmentTag = var.environment_tag
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.environment_tag}-nat-eip"
    EnvironmentTag = var.environment_tag
  }

  depends_on = [aws_internet_gateway.main]
}

# NAT Gateway
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.environment_tag}-nat-gateway"
    EnvironmentTag = var.environment_tag
  }

  depends_on = [aws_internet_gateway.main]
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.environment_tag}-public-rt"
    EnvironmentTag = var.environment_tag
  }
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.environment_tag}-private-rt"
    EnvironmentTag = var.environment_tag
  }
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  count          = var.public_subnet_2_cidr != "" && var.availability_zone_2 != "" ? 1 : 0
  subnet_id      = aws_subnet.public_2[0].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# VPC Endpoints for AWS Services (optional but recommended)
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"
  route_table_ids = [
    aws_route_table.private.id
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.environment_tag}-s3-endpoint"
    EnvironmentTag = var.environment_tag
  }
}

data "aws_region" "current" {}
