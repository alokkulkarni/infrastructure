# Quick Start: OIDC vs Access Keys

## Current Approach (Access Keys - Less Secure)

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: us-east-1
```

**GitHub Secrets Required:**
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

**Security Risks:**
- ❌ Long-lived credentials
- ❌ Can be stolen if repo compromised
- ❌ Manual rotation required
- ❌ Hard to audit

## Recommended Approach (OIDC - Secure)

```yaml
permissions:
  id-token: write   # Required for OIDC
  contents: read

steps:
  - name: Configure AWS credentials using OIDC
    uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
      aws-region: us-east-1
      role-session-name: GitHubActions
```

**GitHub Secrets Required:**
- `AWS_ROLE_ARN` (e.g., `arn:aws:iam::123456789012:role/github-actions-role`)

**Security Benefits:**
- ✅ Temporary credentials (auto-expire)
- ✅ No static credentials in GitHub
- ✅ Automatic rotation
- ✅ Full CloudTrail audit trail
- ✅ Fine-grained permissions

## Setup Steps (5 minutes)

### Option 1: Bootstrap with Terraform (Recommended)

```bash
# 1. Create temporary bootstrap directory
mkdir /tmp/aws-oidc-bootstrap && cd /tmp/aws-oidc-bootstrap

# 2. Download bootstrap config
# (See OIDC_SETUP.md for full configuration)

# 3. Apply with temporary AWS credentials
export AWS_ACCESS_KEY_ID="temp-key"
export AWS_SECRET_ACCESS_KEY="temp-secret"
terraform init && terraform apply

# 4. Copy the role ARN from output
# 5. Add to GitHub secrets as AWS_ROLE_ARN
# 6. Done! Delete temp directory
```

### Option 2: AWS Console (Manual)

```bash
# 1. IAM → Identity providers → Add provider
#    URL: https://token.actions.githubusercontent.com
#    Audience: sts.amazonaws.com

# 2. IAM → Roles → Create role
#    Type: Web identity
#    Provider: GitHub
#    Trust: repo:YOUR_ORG/YOUR_REPO:*

# 3. Copy role ARN
# 4. Add to GitHub secrets as AWS_ROLE_ARN
```

## Migration Path

```bash
# 1. Keep current workflow as backup
cp .github/workflows/deploy.yml .github/workflows/deploy-legacy.yml

# 2. Update workflow to use OIDC
cp .github/workflows/deploy-oidc.yml .github/workflows/deploy.yml

# 3. Test OIDC workflow
# Run workflow and verify success

# 4. Remove old secrets
# Delete AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY from GitHub

# 5. Clean up (optional)
# Delete deploy-legacy.yml after confirming OIDC works
```

## Comparison

| Feature | Access Keys | OIDC |
|---------|-------------|------|
| Setup Time | 2 min | 5 min |
| Security | ⚠️ Low | ✅ High |
| Credential Lifetime | Indefinite | 1 hour |
| Rotation | Manual | Automatic |
| Audit Trail | Limited | Full CloudTrail |
| Risk if Leaked | High | None |
| AWS Best Practice | ❌ No | ✅ Yes |

## Files Changed

### New Files
- `terraform/modules/iam-oidc/` - OIDC IAM role module
- `.github/workflows/deploy-aws-infrastructure-oidc.yml` - OIDC workflow
- `OIDC_SETUP.md` - Complete setup guide

### Updated Files
- `terraform/main.tf` - Added IAM OIDC module
- `terraform/variables.tf` - Added OIDC variables
- `terraform/outputs.tf` - Added role ARN output
- `terraform/terraform.tfvars.example` - Added OIDC config

### Removed Dependencies
- No more `AWS_ACCESS_KEY_ID` secret needed
- No more `AWS_SECRET_ACCESS_KEY` secret needed

### New Dependencies
- `AWS_ROLE_ARN` secret (one-time setup)
- GitHub OIDC provider in AWS (one-time setup)

## Next Steps

1. Read full setup guide: `OIDC_SETUP.md`
2. Choose setup method (Terraform or Console)
3. Complete setup (5 minutes)
4. Test OIDC workflow
5. Remove old access keys
6. 🎉 Enjoy improved security!
