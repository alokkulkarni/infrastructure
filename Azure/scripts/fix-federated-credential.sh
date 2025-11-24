#!/bin/bash
set -e

# Configuration
APP_NAME="testcontainers-dev-github-actions"  # Adjust if different
GITHUB_ORG="alokkulkarni"
GITHUB_REPO="beneficiaries"

echo "Fixing Azure federated credential for correct repository..."
echo "Current repo: $GITHUB_ORG/$GITHUB_REPO"
echo ""

# Get app info
APP_ID=$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv)
OBJECT_ID=$(az ad app list --display-name "$APP_NAME" --query '[0].id' -o tsv)

if [ -z "$APP_ID" ]; then
    echo "❌ App registration '$APP_NAME' not found!"
    echo "Available apps:"
    az ad app list --query "[].{name:displayName, appId:appId}" -o table
    exit 1
fi

echo "✅ Found app: $APP_NAME"
echo "   App ID: $APP_ID"
echo "   Object ID: $OBJECT_ID"
echo ""

# List current federated credentials
echo "Current federated credentials:"
az ad app federated-credential list --id "$OBJECT_ID" --query "[].{name:name, subject:subject}" -o table
echo ""

# Get credential ID for the incorrect one
OLD_CRED_ID=$(az ad app federated-credential list --id "$OBJECT_ID" \
  --query "[?contains(subject, 'infrastructure')].id" -o tsv | head -1)

if [ -n "$OLD_CRED_ID" ]; then
    echo "Found incorrect credential (references 'infrastructure' repo)"
    read -p "Delete it? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        az ad app federated-credential delete --id "$OBJECT_ID" --federated-credential-id "$OLD_CRED_ID"
        echo "✅ Deleted old credential"
    fi
fi

# Create new credential for main branch
echo ""
echo "Creating federated credential for: repo:$GITHUB_ORG/$GITHUB_REPO:ref:refs/heads/main"
az ad app federated-credential create \
  --id "$OBJECT_ID" \
  --parameters "{
    \"name\": \"github-actions-main\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:$GITHUB_ORG/$GITHUB_REPO:ref:refs/heads/main\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" 2>/dev/null && echo "✅ Created federated credential for main branch" || echo "⚠️  Credential may already exist"

# Create credential for pull requests
echo ""
echo "Creating federated credential for pull requests"
az ad app federated-credential create \
  --id "$OBJECT_ID" \
  --parameters "{
    \"name\": \"github-actions-pr\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:$GITHUB_ORG/$GITHUB_REPO:pull_request\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" 2>/dev/null && echo "✅ Created federated credential for PRs" || echo "⚠️  Credential may already exist"

echo ""
echo "✅ Setup complete!"
echo ""
echo "Updated federated credentials:"
az ad app federated-credential list --id "$OBJECT_ID" --query "[].{name:name, subject:subject}" -o table
