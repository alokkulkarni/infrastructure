# Backend Container Name Fix

## Issue

The destroy workflow was failing with "Bad Request - Invalid URL" error when trying to access the Terraform state file in Azure Storage:

```
Error: Failed to get existing workspaces: containers.Client#ListBlobs: Failure responding to request: 
StatusCode=400 -- Original Error: autorest/azure: Service returned an error. 
Status=400 Code="InvalidUrl" Message="Bad Request - Invalid URL"
```

## Root Cause

The deploy and destroy workflows were using **different container naming strategies**:

### Deploy Workflow (CORRECT)
- Uses dynamic container name derived from environment tag
- Container name: `{environment-tag-lowercase}` (e.g., `sit-user-team-20251125-1400`)
- Configuration: `container_name = "${{ needs.setup-backend.outputs.backend_container }}"`

### Destroy Workflow (INCORRECT - Before Fix)
- Used hardcoded container name
- Container name: `tfstate` (hardcoded)
- Configuration: `container_name = "tfstate"`

When the destroy workflow tried to access the `tfstate` container, Azure returned a 400 Bad Request because that container didn't exist. The actual state file was stored in a container named after the environment tag.

## Backend Storage Structure

```
Storage Account: tctfstate{subscription-id}  (17 chars)
├── Container: {env-tag-lowercase}           (e.g., "sit-user-team-20251125-1400")
│   └── Blob: azure/{environment}/{environment_tag}/terraform.tfstate
│
└── (Other environment containers...)
```

## Solution

Updated the destroy workflow to derive the container name dynamically, matching the deploy workflow:

### Changes Made

1. **Added container name derivation** to `setup-backend` job:
   ```yaml
   # Container name based on environment tag for isolation (same logic as deploy)
   CONTAINER_NAME=$(echo "${{ env.ENVIRONMENT_TAG }}" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
   echo "backend_container=${CONTAINER_NAME}" >> $GITHUB_OUTPUT
   ```

2. **Updated backend configuration** to use dynamic container:
   ```yaml
   container_name = "${{ needs.setup-backend.outputs.backend_container }}"
   ```

## Container Name Derivation Logic

Both deploy and destroy workflows now use identical logic:

```bash
# Convert environment tag to valid container name
# - Lowercase all characters
# - Replace underscores with hyphens
CONTAINER_NAME=$(echo "$ENVIRONMENT_TAG" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
```

### Examples:
- `SIT_User_Team_20251125_1400` → `sit-user-team-20251125-1400`
- `PROD_Main_20251201_1000` → `prod-main-20251201-1000`
- `dev_test` → `dev-test`

## Azure Storage Naming Constraints

### Storage Account Names
- Length: 3-24 characters
- Allowed: Lowercase letters and numbers only
- Our format: `tctfstate{subscription-id}` = 17 chars ✅

### Container Names
- Length: 3-63 characters
- Allowed: Lowercase letters, numbers, hyphens
- Must start/end with letter or number
- Our format: `{env-tag-lowercase}` with underscores → hyphens

## Validation

To verify the fix works correctly:

1. **Check container exists**:
   ```bash
   az storage container list \
     --account-name tctfstate{subscription-id} \
     --auth-mode login \
     --query "[].name"
   ```

2. **Verify state file path**:
   ```bash
   az storage blob list \
     --account-name tctfstate{subscription-id} \
     --container-name {env-tag-lowercase} \
     --prefix "azure/" \
     --auth-mode login
   ```

3. **Test destroy workflow**:
   - Run deploy workflow first (creates infrastructure + state)
   - Note the environment tag used
   - Run destroy workflow with same environment tag
   - Should successfully initialize and find state file

## Benefits of Environment-Specific Containers

1. **Isolation**: Each environment tag gets its own container
2. **Multi-tenant**: Multiple teams/environments can share same storage account
3. **Organized**: Easy to identify and manage per-environment state files
4. **Cleanup**: Can delete entire container when environment is no longer needed

## Files Modified

- `.github/workflows/destroy-azure-infrastructure.yml`:
  - Line 64: Added container name derivation
  - Line 120: Changed from hardcoded to dynamic container name

## Related Documentation

- [Azure Storage Account Name Fix](./STORAGE_ACCOUNT_NAME_FIX.md) - Previous fix for storage account name length
- [Destroy Validation Guide](./DESTROY_VALIDATION.md) - Complete resource destruction documentation
- [setup-terraform-backend.sh](./scripts/setup-terraform-backend.sh) - Backend setup script with container logic

## Testing

After applying this fix:

1. ✅ Deploy workflow creates container: `{env-tag-lowercase}`
2. ✅ Deploy workflow stores state: `azure/{env}/{env_tag}/terraform.tfstate`
3. ✅ Destroy workflow derives same container name
4. ✅ Destroy workflow finds state file
5. ✅ Destroy workflow successfully destroys all resources

## Lessons Learned

1. **Keep workflows synchronized**: Deploy and destroy must use identical backend configuration
2. **Avoid hardcoded values**: Dynamic resource names require dynamic configuration
3. **Test destroy after deploy changes**: Backend changes must be reflected in both workflows
4. **Azure error messages can be cryptic**: "Bad Request - Invalid URL" actually meant "container not found"
5. **Document naming conventions**: Clear documentation prevents configuration mismatches
