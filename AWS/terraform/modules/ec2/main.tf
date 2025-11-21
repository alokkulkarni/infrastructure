# Get latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# IAM Role for EC2
resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-${var.environment}-${var.environment_tag}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name           = "${var.project_name}-${var.environment}-${var.environment_tag}-ec2-role"
    Environment    = var.environment
    EnvironmentTag = var.environment_tag
  }
}

# IAM Policy for EC2 (ECR, S3, CloudWatch)
resource "aws_iam_role_policy" "ec2" {
  name = "${var.project_name}-${var.environment}-${var.environment_tag}-ec2-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-${var.environment}-${var.environment_tag}-ec2-profile"
  role = aws_iam_role.ec2.name

  tags = {
    Name           = "${var.project_name}-${var.environment}-${var.environment_tag}-ec2-profile"
    Environment    = var.environment
    EnvironmentTag = var.environment_tag
  }
}

# User Data Script
# Use lightweight script for custom AMI, full script for standard Ubuntu AMI
locals {
  user_data_script = var.use_custom_ami ? "user-data-ami.sh" : "user-data.sh"
  user_data_template = templatefile("${path.module}/${local.user_data_script}", {
    github_pat           = var.github_pat
    github_runner_token  = var.github_runner_token
    github_repo_url      = var.github_repo_url
    github_runner_name   = var.github_runner_name
    github_runner_labels = join(",", var.github_runner_labels)
  })
}

# EC2 Instance (in private subnet, accessed via ALB)
resource "aws_instance" "main" {
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  # Use user_data_base64 with gzip to handle large scripts (>16KB)
  user_data_base64 = base64gzip(local.user_data_template)

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-runner"
  }

  lifecycle {
    ignore_changes = [user_data_base64]
  }
}
