terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment    = var.environment
      EnvironmentTag = var.environment_tag
      Project        = var.project_name
      ManagedBy      = "Terraform"
    }
  }
}

# IAM OIDC Module for GitHub Actions
module "iam_oidc" {
  source = "./modules/iam-oidc"

  project_name           = var.project_name
  environment            = var.environment
  environment_tag        = var.environment_tag
  github_org             = var.github_org
  github_repo            = var.github_repo
  terraform_state_bucket = var.terraform_state_bucket
  terraform_lock_table   = var.terraform_lock_table
}

# VPC and Networking
module "networking" {
  source = "./modules/networking"

  project_name         = var.project_name
  environment          = var.environment
  environment_tag      = var.environment_tag
  vpc_cidr             = var.vpc_cidr
  availability_zone    = var.availability_zone
  availability_zone_2  = var.availability_zone_2
  public_subnet_cidr   = var.public_subnet_cidr
  public_subnet_2_cidr = var.public_subnet_2_cidr
  private_subnet_cidr  = var.private_subnet_cidr
}

# Security Groups
module "security" {
  source = "./modules/security"

  project_name    = var.project_name
  environment     = var.environment
  environment_tag = var.environment_tag
  vpc_id          = module.networking.vpc_id
}

# EC2 Instance
module "ec2" {
  source = "./modules/ec2"

  project_name         = var.project_name
  environment          = var.environment
  environment_tag      = var.environment_tag
  instance_type        = var.instance_type
  ami_id               = var.ami_id
  subnet_id            = module.networking.private_subnet_id
  security_group_ids   = [module.security.ec2_security_group_id]
  github_runner_token  = var.github_runner_token
  github_repo_url      = var.github_repo_url
  github_runner_name   = var.github_runner_name
  github_runner_labels = var.github_runner_labels
}

# Application Load Balancer
module "alb" {
  source = "./modules/alb"

  project_name      = var.project_name
  environment       = var.environment
  environment_tag   = var.environment_tag
  vpc_id            = module.networking.vpc_id
  public_subnet_ids = module.networking.public_subnet_ids
  ec2_instance_id   = module.ec2.instance_id

  depends_on = [module.ec2]
}

# Update EC2 security group to allow ALB traffic
resource "aws_vpc_security_group_ingress_rule" "ec2_from_alb" {
  security_group_id = module.security.ec2_security_group_id
  description       = "HTTP from ALB"

  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  referenced_security_group_id = module.alb.alb_security_group_id

  depends_on = [module.alb, module.security]
}
