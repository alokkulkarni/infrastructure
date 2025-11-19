#!/bin/bash
# Script to generate GitHub runner token dynamically
# This uses GitHub CLI (gh) to generate a registration token

set -e

if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed."
    echo "Install it from: https://cli.github.com/"
    exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo "Error: Not authenticated with GitHub CLI."
    echo "Run: gh auth login"
    exit 1
fi

# Get repository from argument or use default
REPO="${1:-}"
if [ -z "$REPO" ]; then
    echo "Usage: $0 <owner/repo>"
    echo "Example: $0 alokkulkarni/sit-test-repo"
    exit 1
fi

echo "Generating runner registration token for: $REPO"

# Generate token
TOKEN=$(gh api \
    --method POST \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "/repos/$REPO/actions/runners/registration-token" \
    --jq '.token')

if [ -z "$TOKEN" ]; then
    echo "Error: Failed to generate token"
    exit 1
fi

echo "Token generated successfully!"
echo ""
echo "Export it as an environment variable:"
echo "export TF_VAR_github_runner_token=\"$TOKEN\""
echo ""
echo "Or use it directly in terraform:"
echo "terraform apply -var=\"github_runner_token=$TOKEN\""
