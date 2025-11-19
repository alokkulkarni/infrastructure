/**
 * IAM OIDC Module for GitHub Actions
 * 
 * Creates IAM role that GitHub Actions can assume via OIDC federation
 * Eliminates the need for long-lived AWS credentials
 */

# GitHub OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = {
    Name        = "${var.project_name}-${var.environment}-github-oidc"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name               = "${var.project_name}-${var.environment}-github-actions-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = {
    Name        = "${var.project_name}-${var.environment}-github-actions-role"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Assume Role Policy - allows GitHub Actions to assume this role
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Format: repo:OWNER/REPO:ref:refs/heads/BRANCH or repo:OWNER/REPO:*
      values = [
        "repo:${var.github_org}/${var.github_repo}:*"
      ]
    }
  }
}

# IAM Policy for GitHub Actions - Terraform operations
data "aws_iam_policy_document" "github_actions_permissions" {
  # EC2 permissions
  statement {
    sid    = "EC2Permissions"
    effect = "Allow"
    actions = [
      "ec2:*",
    ]
    resources = ["*"]
  }

  # VPC permissions
  statement {
    sid    = "VPCPermissions"
    effect = "Allow"
    actions = [
      "ec2:*Vpc*",
      "ec2:*Subnet*",
      "ec2:*Gateway*",
      "ec2:*Route*",
      "ec2:*SecurityGroup*",
      "ec2:*NetworkAcl*",
      "ec2:*VpcEndpoint*",
    ]
    resources = ["*"]
  }

  # IAM permissions for creating roles and policies
  statement {
    sid    = "IAMPermissions"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:PassRole",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagRole",
      "iam:TagPolicy",
      "iam:TagInstanceProfile",
    ]
    resources = ["*"]
  }

  # S3 permissions for Terraform state
  statement {
    sid    = "S3StatePermissions"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketVersioning",
      "s3:GetBucketLocation",
      "s3:CreateBucket",
      "s3:PutBucketVersioning",
      "s3:PutBucketEncryption",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketTagging",
    ]
    resources = [
      "arn:aws:s3:::${var.terraform_state_bucket}",
      "arn:aws:s3:::${var.terraform_state_bucket}/*",
    ]
  }

  # DynamoDB permissions for state locking
  statement {
    sid    = "DynamoDBLockPermissions"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
      "dynamodb:CreateTable",
      "dynamodb:UpdateTable",
      "dynamodb:TagResource",
    ]
    resources = [
      "arn:aws:dynamodb:*:*:table/${var.terraform_lock_table}",
    ]
  }

  # CloudWatch Logs permissions
  statement {
    sid    = "CloudWatchLogsPermissions"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["*"]
  }

  # Systems Manager permissions (for Session Manager)
  statement {
    sid    = "SSMPermissions"
    effect = "Allow"
    actions = [
      "ssm:DescribeInstanceInformation",
      "ssm:GetConnectionStatus",
      "ssm:DescribeInstanceProperties",
    ]
    resources = ["*"]
  }
}

# Attach the policy to the role
resource "aws_iam_role_policy" "github_actions" {
  name   = "${var.project_name}-${var.environment}-github-actions-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}
