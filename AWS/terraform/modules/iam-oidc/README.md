# IAM OIDC Module for GitHub Actions

This module creates an IAM role that GitHub Actions can assume using OIDC (OpenID Connect) federation, eliminating the need for long-lived AWS credentials.

## Features

- **OIDC Provider Management**: Intelligently handles existing GitHub OIDC providers
- **Automatic Import**: Workflow automatically imports existing OIDC providers to prevent conflicts
- **Environment Isolation**: Separate IAM roles per environment while sharing the OIDC provider
- **Security Best Practices**: Uses web identity federation with specific repository restrictions

## Idempotent Design

### Problem
AWS only allows one OIDC provider per URL (`https://token.actions.githubusercontent.com`). If you:
1. Created the OIDC provider manually in AWS Console (to get the ARN for secrets)
2. Run Terraform to create infrastructure

You would get this error:
```
Error: creating IAM OIDC Provider: EntityAlreadyExists: 
Provider with url https://token.actions.githubusercontent.com already exists.
```

### Solution

This module is designed to work with existing OIDC providers:

1. **Automatic Import**: The workflow includes an import script (`import-existing-oidc.sh`) that runs before Terraform operations
2. **State Management**: If the OIDC provider exists in AWS but not in Terraform state, it's automatically imported
3. **Shared Resource**: The OIDC provider is tagged as `Environment = "shared"` because it's used across all environments

### How It Works

The workflow runs this sequence:
```bash
terraform init
→ import-existing-oidc.sh  # Checks and imports existing OIDC provider
→ terraform plan/apply      # Now aware of existing resources
```

The import script:
- Checks if OIDC provider exists in AWS
- Checks if it's already in Terraform state
- Imports it if needed: `terraform import module.iam_oidc.aws_iam_openid_connect_provider.github <ARN>`

## Usage

### In Terraform Configuration

```hcl
module "iam_oidc" {
  source = "./modules/iam-oidc"
  
  project_name = "testcontainers"
  environment  = "dev"
  
  github_org  = "your-org"
  github_repo = "your-repo"
  
  terraform_state_bucket = aws_s3_bucket.tfstate.id
  terraform_lock_table   = aws_dynamodb_table.tflock.id
}
```

### In GitHub Actions Workflow

The workflow automatically handles OIDC provider import:

```yaml
- name: Terraform Init
  run: terraform init

- name: Import existing OIDC provider if present
  run: |
    chmod +x scripts/import-existing-oidc.sh
    cd terraform
    ../scripts/import-existing-oidc.sh

- name: Terraform Plan
  run: terraform plan
```

## Resource Sharing

### Shared Across Environments
- **OIDC Provider**: One provider serves all environments (dev, staging, prod)
  - Tagged with `Environment = "shared"`
  - URL: `https://token.actions.githubusercontent.com`

### Per-Environment
- **IAM Role**: Each environment gets its own role
  - Named: `{project_name}-{environment}-github-actions-role`
  - Tagged with specific environment

## Permissions

The IAM role includes permissions for:
- EC2 instance management
- VPC and networking configuration
- IAM role/policy/instance profile management
- S3 state management
- DynamoDB state locking
- CloudWatch Logs
- Systems Manager (Session Manager)

## Security

- **Repository Restriction**: Role can only be assumed by specified GitHub repository
- **Web Identity Federation**: Uses OIDC tokens instead of long-lived credentials
- **Least Privilege**: Only includes permissions needed for Terraform operations
- **Thumbprint Rotation**: Lifecycle policy ignores thumbprint changes (GitHub may rotate certificates)

## Outputs

- `github_actions_role_arn`: ARN of the IAM role to use in GitHub Actions
- `github_actions_role_name`: Name of the IAM role
- `oidc_provider_arn`: ARN of the GitHub OIDC provider

## Manual Import (if needed)

If you need to manually import the OIDC provider:

```bash
# Get your AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Import the OIDC provider
terraform import \
  module.iam_oidc.aws_iam_openid_connect_provider.github \
  "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
```

## Troubleshooting

### Error: EntityAlreadyExists

If you see this error, the OIDC provider exists but isn't in Terraform state:

**Solution**: Run the import script manually:
```bash
cd infrastructure/AWS
./scripts/import-existing-oidc.sh
```

Or import directly:
```bash
cd infrastructure/AWS/terraform
terraform import \
  module.iam_oidc.aws_iam_openid_connect_provider.github \
  arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com
```

### Multiple Environments

When deploying multiple environments:
1. First environment creates the OIDC provider
2. Subsequent environments automatically import it
3. Each environment gets its own IAM role
4. All share the same OIDC provider

## Best Practices

1. **Let Terraform Manage**: Once imported, let Terraform manage the OIDC provider
2. **Don't Delete Manually**: If you delete the OIDC provider from AWS, update Terraform state:
   ```bash
   terraform state rm module.iam_oidc.aws_iam_openid_connect_provider.github
   ```
3. **Verify Import**: After import, run `terraform plan` to verify no changes are needed
4. **State Backup**: Always backup state before manual imports

## References

- [AWS OIDC Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
