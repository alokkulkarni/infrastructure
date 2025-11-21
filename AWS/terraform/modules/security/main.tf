# Security Group for EC2 Instance
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-${var.environment}-${var.environment_tag}-ec2-sg"
  description = "Security group for EC2 instance with Docker and GitHub Actions runner"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.environment_tag}-ec2-sg"
    EnvironmentTag = var.environment_tag
  }
}

# Note: HTTP ingress from ALB is added in main.tf after ALB is created

# Egress Rules - All traffic (needed for GitHub Actions runner)
resource "aws_vpc_security_group_egress_rule" "all_traffic" {
  security_group_id = aws_security_group.ec2.id
  description       = "Allow all outbound traffic"

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

# Egress Rules - HTTPS to GitHub (443)
resource "aws_vpc_security_group_egress_rule" "github_https" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTPS to GitHub"

  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
  cidr_ipv4   = "0.0.0.0/0"
}

# Egress Rules - HTTP for package downloads
resource "aws_vpc_security_group_egress_rule" "http_out" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTP for package downloads"

  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"
  cidr_ipv4   = "0.0.0.0/0"
}

# Egress Rules - DNS
resource "aws_vpc_security_group_egress_rule" "dns_tcp" {
  security_group_id = aws_security_group.ec2.id
  description       = "DNS TCP"

  from_port   = 53
  to_port     = 53
  ip_protocol = "tcp"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "dns_udp" {
  security_group_id = aws_security_group.ec2.id
  description       = "DNS UDP"

  from_port   = 53
  to_port     = 53
  ip_protocol = "udp"
  cidr_ipv4   = "0.0.0.0/0"
}
