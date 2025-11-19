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

output "bastion_public_ip" {
  description = "Public IP of bastion host (if needed for SSH access)"
  value       = module.networking.nat_gateway_public_ip
}

output "ec2_security_group_id" {
  description = "ID of the EC2 security group"
  value       = module.security.ec2_security_group_id
}

output "github_actions_role_arn" {
  description = "ARN of the IAM role for GitHub Actions (use this in workflow)"
  value       = module.iam_oidc.github_actions_role_arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = module.iam_oidc.oidc_provider_arn
}
