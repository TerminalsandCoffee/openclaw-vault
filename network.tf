# --- VPC ---
resource "aws_vpc" "openclaw" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "openclaw-vpc" }
}

# --- Internet Gateway ---
resource "aws_internet_gateway" "openclaw" {
  vpc_id = aws_vpc.openclaw.id

  tags = { Name = "openclaw-igw" }
}

# --- Availability Zones ---
data "aws_availability_zones" "available" {
  state = "available"
}

# --- Subnet ---
# Public IP is required for outbound internet (apt, Tailscale, npm) without a NAT Gateway.
# The security group has zero inbound rules, so the public IP has no listening attack surface.
# For production, replace with a private subnet + NAT Gateway (~$32/month extra).
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.openclaw.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = { Name = "openclaw-subnet" }
}

# --- Route Table ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.openclaw.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.openclaw.id
  }

  tags = { Name = "openclaw-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
