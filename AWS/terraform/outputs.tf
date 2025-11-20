output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = module.networking.public_subnet_id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = module.networking.private_subnet_id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = module.networking.nat_gateway_id
}

output "ec2_instance_id" {
  description = "ID of the EC2 instance"
  value       = module.ec2.instance_id
}

output "ec2_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = module.ec2.private_ip
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "nginx_url" {
  description = "URL to access the Nginx reverse proxy server (via ALB)"
  value       = "http://${module.alb.alb_dns_name}"
}

output "nginx_health_check" {
  description = "URL for Nginx health check endpoint"
  value       = "http://${module.alb.alb_dns_name}/health"
}

output "bastion_public_ip" {
  description = "Public IP of NAT Gateway (for reference)"
  value       = module.networking.nat_gateway_public_ip
}

output "ec2_security_group_id" {
  description = "ID of the EC2 security group"
  value       = module.security.ec2_security_group_id
}

# Get existing OIDC resources (created manually, not managed by Terraform)
data "aws_iam_role" "github_actions" {
  name = "${var.project_name}-${var.environment}-github-actions-role"
}

data "aws_caller_identity" "current" {}

output "github_actions_role_arn" {
  description = "ARN of the IAM role for GitHub Actions (existing, not managed by Terraform)"
  value       = data.aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider (existing, not managed by Terraform)"
  value       = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}
