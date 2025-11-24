#!/bin/bash
set -e

# Configuration
APP_NAME="testcontainers-dev-github-actions"  # Adjust if different
GITHUB_ORG="alokkulkarni"

echo "Setting up organization-level federated credential..."
echo "This will allow ANY repo under '$GITHUB_ORG' to authenticate"
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

# Create organization-level credential (all repos, all branches)
echo "Creating organization-level credential: repo:$GITHUB_ORG/*:*"
az ad app federated-credential create \
  --id "$OBJECT_ID" \
  --parameters "{
    \"name\": \"github-actions-org-all\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:$GITHUB_ORG/*:*\",
    \"audiences\": [\"api://AzureADTokenExchange\"],
    \"description\": \"All repos in organization - all branches and contexts\"
  }" 2>/dev/null && echo "✅ Created organization-level credential" || echo "⚠️  Credential may already exist"

echo ""
echo "✅ Setup complete!"
echo ""
echo "This credential allows authentication from:"
echo "  - Any repository under $GITHUB_ORG"
echo "  - Any branch"
echo "  - Pull requests"
echo "  - Any workflow context"
echo ""
echo "Updated federated credentials:"
az ad app federated-credential list --id "$OBJECT_ID" --query "[].{name:name, subject:subject}" -o table
