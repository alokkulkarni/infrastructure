# Quick Fix: GitHub Secrets with Trailing Newlines

## The Problem

If you see this error in GitHub Actions:

```
Error: populating Resource Provider cache: loading results: building GET request: 
parse "https://management.azure.com/subscriptions/***\n/providers": 
net/url: invalid control character in URL
```

Your GitHub Secrets contain **trailing newlines** (`\n`) or whitespace that break Azure API URLs.

## Quick Fix (5 minutes)

### Step 1: Get Clean Values

Run the OIDC setup script to get clean values:

```bash
cd infrastructure/Azure/scripts
./setup-oidc-manually.sh alokkulkarni infrastructure dev
```

The script will output:
```
AZURE_CLIENT_ID:       f0b334e4-909c-44a0-a2ee-db4c7b1d066c
AZURE_TENANT_ID:       150ed8e1-32c6-4a96-ab48-b85ad2138c52
AZURE_SUBSCRIPTION_ID: 2745ace7-ad28-4d41-ae4c-eeb28f54ffd2
```

### Step 2: Update GitHub Secrets Carefully

For **each** secret:

1. Go to: `https://github.com/YOUR_ORG/YOUR_REPO/settings/secrets/actions`

2. Click the secret name (e.g., `AZURE_CLIENT_ID`)

3. Click **"Update"**

4. **CAREFULLY** paste the value:
   - **Select and copy** the value from terminal (e.g., `f0b334e4-909c-44a0-a2ee-db4c7b1d066c`)
   - **Paste** into the value field
   - **DO NOT press Enter** after pasting
   - **Click "Update secret"** immediately

5. Repeat for all three secrets:
   - `AZURE_CLIENT_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_SUBSCRIPTION_ID`

### Step 3: Verify

Re-run your GitHub Actions workflow. The error should be gone!

## What Causes This?

### ❌ Wrong Ways to Add Secrets

```bash
# Method 1: Copying from file with newline
echo "2745ace7-ad28-4d41-ae4c-eeb28f54ffd2" > sub.txt
# Opening sub.txt and copying (includes newline from echo)

# Method 2: Pressing Enter after pasting
# Paste value → Press Enter → Click Update
# The Enter key adds a newline character

# Method 3: Copying from some text editors
# Some editors add trailing newlines automatically
```

### ✅ Correct Ways to Add Secrets

```bash
# Method 1: Copy directly from terminal output
./setup-oidc-manually.sh alokkulkarni infrastructure dev
# Select only the value, not the label or trailing space

# Method 2: Use echo -n to avoid newlines
echo -n "2745ace7-ad28-4d41-ae4c-eeb28f54ffd2"
# Copy the output

# Method 3: Paste without pressing Enter
# Paste → Immediately click "Update secret"
```

## How to Check if Your Secrets Are Clean

### GitHub Actions Workflow

Add a debug step to your workflow:

```yaml
- name: Debug secrets
  run: |
    echo "Client ID length: ${#AZURE_CLIENT_ID}"
    echo "Subscription ID length: ${#AZURE_SUBSCRIPTION_ID}"
    # If length is more than expected (36 chars for GUIDs), you have extra chars
```

### Expected Lengths

- **CLIENT_ID**: 36 characters (GUID format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)
- **TENANT_ID**: 36 characters (GUID format)
- **SUBSCRIPTION_ID**: 36 characters (GUID format)

If you see 37+ characters, you have trailing newlines/spaces.

## Prevention Tips

1. **Always copy from command output**, not text files
2. **Never press Enter** after pasting into GitHub Secrets field
3. **Use the OIDC setup script** which outputs clean values
4. **Verify immediately** after creating secrets by checking length
5. **Use GitHub Actions workflow output** as the source of truth

## Already Fixed in Workflow

Good news! The workflow now **automatically sanitizes** all secrets:

```yaml
- name: Sanitize Azure secrets
  run: |
    # Strip any trailing newlines/whitespace
    echo "ARM_CLIENT_ID=$(echo -n '${{ secrets.AZURE_CLIENT_ID }}' | tr -d '\n\r' | xargs)" >> $GITHUB_ENV
    echo "ARM_TENANT_ID=$(echo -n '${{ secrets.AZURE_TENANT_ID }}' | tr -d '\n\r' | xargs)" >> $GITHUB_ENV
    echo "ARM_SUBSCRIPTION_ID=$(echo -n '${{ secrets.AZURE_SUBSCRIPTION_ID }}' | tr -d '\n\r' | xargs)" >> $GITHUB_ENV
```

This means:
- ✅ **If you've already updated to latest workflow**: Just re-run, it should work
- ✅ **If error persists**: Clean the secrets manually (steps above)
- ✅ **For new setups**: Follow prevention tips to avoid the issue

## Related Documentation

- [AUTOMATION_SETUP.md](./AUTOMATION_SETUP.md) - Complete OIDC setup guide
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - All common errors and solutions
- [GitHub Docs: Encrypted Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)

## Still Having Issues?

1. **Delete and recreate secrets** (don't just update)
2. **Copy values character by character** to ensure accuracy
3. **Check Azure Portal** to verify IDs are correct:
   - Go to Azure Active Directory → App registrations
   - Find your app: `testcontainers-dev-github-actions`
   - Compare Application (client) ID, Directory (tenant) ID
4. **Run setup script again** to confirm values haven't changed
5. **Check workflow logs** for other errors that might be related

## Summary

**The Fix:**
1. Get clean values from setup script
2. Update GitHub Secrets carefully (no Enter key!)
3. Re-run workflow

**The Prevention:**
- Copy from terminal, not files
- Don't press Enter after pasting
- Let workflow sanitization handle any issues

**The Result:**
- No more URL parsing errors
- Smooth Azure authentication
- Happy deployments! 🎉
