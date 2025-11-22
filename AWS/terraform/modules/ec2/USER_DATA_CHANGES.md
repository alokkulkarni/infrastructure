# User Data Script Changes

## Fixed Issues
1. ✅ **Syntax errors removed** - Script now works correctly as a Terraform template
2. ✅ **Runner registration restored** - Uses GitHub PAT → generates runner token → registers runner
3. ✅ **Proper escaping** - All `$$` and `%%` correctly escaped for Terraform template processing

## How It Works

### Variables Required in Terraform
- `github_pat` - GitHub Personal Access Token (not `github_runner_token`)
- `github_repo_url` - Full repository URL
- `github_runner_name` - Name for the runner
- `github_runner_labels` - Comma-separated labels

### Authentication Flow
1. Script receives GitHub PAT from Terraform variable
2. Authenticates `gh` CLI with the PAT
3. Uses `gh api` to generate a runner registration token
4. Registers the runner with the generated token
5. Clears PAT from environment for security

### Key Differences from Previous Version
- **Before**: Expected pre-generated `runner_token` from Terraform (doesn't work)
- **After**: Generates token dynamically using GitHub API (works correctly)

## Testing
This is a Terraform template file - bash syntax checking will fail on the raw file.
The file will be valid bash AFTER Terraform processes it with `templatefile()`.

## File Structure
- Lines 1-80: Setup, verification, and connectivity checks
- Lines 81-190: GitHub authentication and runner configuration
- Lines 191-344: Nginx auto-configuration and service setup
