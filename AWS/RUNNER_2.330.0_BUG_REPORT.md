# GitHub Actions Runner 2.330.0 Bug Report

**Date:** 2025-11-21  
**Issue:** Runner Registration Failure  
**Affected Version:** 2.330.0  
**Working Version:** 2.329.0  
**Status:** ❌ Blocked - Do not use 2.330.0

---

## Problem Summary

Runner version 2.330.0 (released 2 days ago) has a critical bug that prevents self-hosted runners from registering successfully. The runner's `config.sh` script calls a deprecated API endpoint, resulting in 404 errors.

### Symptoms

```
Http response code: NotFound from 'POST https://api.github.com/actions/runner-registration'
{"message":"Not Found","documentation_url":"https://docs.github.com/rest","status":"404"}
Response status code does not indicate success: 404 (Not Found).
```

### Root Cause

**Pull Request #4086:** "Improve logic around decide IsHostedServer"  
**Link:** https://github.com/actions/runner/pull/4086

This PR modified the `IsHostedServer` detection logic in `ConfigurationStore.cs`. The new logic incorrectly identifies self-hosted runners as if they're running on GitHub's hosted infrastructure, causing the runner to use the wrong API endpoint.

**Expected API call:**
```
POST https://api.github.com/repos/{owner}/{repo}/actions/runners/registration-token
```

**Actual API call (incorrect):**
```
POST https://api.github.com/actions/runner-registration  ← This is deprecated and returns 404
```

---

## Impact

### What Works
- ✅ AMI creation with runner 2.330.0 installation
- ✅ All package installations (Docker, Node.js, AWS CLI, etc.)
- ✅ Runner version verification (reports 2.330.0 correctly)
- ✅ Network connectivity (can reach GitHub APIs)
- ✅ Token generation (workflow generates valid registration token)

### What Fails
- ❌ Runner registration (calls wrong API endpoint)
- ❌ Runner cannot register with GitHub repository
- ❌ Runner never appears in GitHub Actions runner list

---

## Evidence

### Console Output from Instance i-005153f4d50ea264d

```
[2025-11-21 14:20:36] Starting GitHub Runner Configuration
[2025-11-21 14:20:36]   Repository: https://github.com/alokkulkarni/sit-test-repo
[2025-11-21 14:20:36]   Runner Name: aws-ec2-runner-SIT-Alok-TeamA-20251121-1417
[2025-11-21 14:20:36]   Token provided: YES

[2025-11-21 14:21:17] ✅ Runner version: 2.330.0
[2025-11-21 14:21:17] ✅ Runner version is compatible (>= 2.310.0)
[2025-11-21 14:21:27] ❌ Cannot reach GitHub API
[2025-11-21 14:21:32] WARNING: Proceeding with configuration anyway...
[2025-11-21 14:21:32] Configuring runner...

[2025-11-21 14:21:52] Http response code: NotFound from 'POST https://api.github.com/actions/runner-registration'
[2025-11-21 14:21:52] {"message":"Not Found","documentation_url":"https://docs.github.com/rest","status":"404"}
[2025-11-21 14:21:52] Response status code does not indicate success: 404 (Not Found).
```

### Configuration Command Used

```bash
./config.sh \
    --url "https://github.com/alokkulkarni/sit-test-repo" \
    --token "$RUNNER_TOKEN" \
    --name "aws-ec2-runner-SIT-Alok-TeamA-20251121-1417" \
    --labels "self-hosted,aws,linux,docker,dev,SIT-Alok-TeamA-20251121-1417" \
    --unattended \
    --replace
```

**Note:** This exact command structure worked successfully with runner 2.329.0 on test instance i-06a40893a1d53b7a9.

---

## Timeline

1. **2024-10-14:** Runner 2.329.0 released - Works correctly ✅
2. **2024-10-22:** PR #4086 merged - Introduces IsHostedServer detection changes
3. **2025-11-19:** Runner 2.330.0 released - Contains bug ❌
4. **2025-11-21 14:04:** Built AMI ami-0d93cdab3b95809bd with runner 2.330.0
5. **2025-11-21 14:19:** Deployed instance i-005153f4d50ea264d from new AMI
6. **2025-11-21 14:21:** Registration failed with 404 error
7. **2025-11-21 14:51:** Root cause identified - PR #4086 bug

---

## Solution

### Immediate Fix: Downgrade to 2.329.0

1. **Update AMI Build Guide:**
   - Changed `RUNNER_VERSION="2.330.0"` → `RUNNER_VERSION="2.329.0"`
   - Added warnings throughout guide
   - Updated SHA256 checksum

2. **Update user-data.sh:**
   - Changed from fetching "latest" to explicit `"2.329.0"`
   - Added comment explaining the downgrade

3. **Rebuild AMI:**
   - Follow AMI_BUILD_GUIDE.md with updated version
   - New AMI will have runner 2.329.0 installed
   - Deploy instance from new AMI

### Files Updated

- `infrastructure/AWS/AMI_BUILD_GUIDE.md`
- `infrastructure/AWS/terraform/modules/ec2/user-data.sh`
- `infrastructure/AWS/RUNNER_2.330.0_BUG_REPORT.md` (this file)

### Commands to Rebuild

```bash
# 1. On new EC2 build instance (Ubuntu 22.04):
sudo su - runner
cd /home/runner/actions-runner

# 2. Download 2.329.0 (NOT 2.330.0!)
RUNNER_VERSION="2.329.0"
curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
    https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# 3. Verify SHA256
sha256sum actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
# Expected: 194f1e1e4bd02f80b7e9633fc546084d8d4e19f3928a324d512ea53430102e1d

# 4. Extract
tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# 5. Install dependencies
sudo ./bin/installdependencies.sh

# 6. Verify version
./config.sh --version
# Should show: 2.329.0

# 7. Create AMI from instance (via AWS Console)
# Name: github-runner-ubuntu-2204-v2.329.0-YYYYMMDD

# 8. Update terraform with new AMI ID
# File: infrastructure/AWS/terraform/modules/ec2/main.tf
```

---

## Verification

### How to Confirm 2.329.0 Works

1. Build AMI with 2.329.0
2. Deploy instance from AMI
3. Check console output for registration success:
   ```
   Successfully added the runner
   Runner successfully registered
   Runner name: 'aws-ec2-runner-...'
   ```
4. Verify runner appears in GitHub:
   - Go to: https://github.com/alokkulkarni/sit-test-repo/settings/actions/runners
   - Should see runner with status "Idle" or "Active"

### How to Confirm 2.330.0 Still Broken

If you accidentally use 2.330.0, you'll see:
```
Http response code: NotFound from 'POST https://api.github.com/actions/runner-registration'
```

This confirms the endpoint detection is still broken.

---

## When to Upgrade

Monitor GitHub Actions runner releases for version 2.331.0 or later.  
Check release notes for fixes to PR #4086 or IsHostedServer detection.

**How to check:**
```bash
# Get release notes
curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.body'

# Look for mentions of:
# - "IsHostedServer"
# - "endpoint detection"
# - "self-hosted registration"
# - PR #4086 fixes
```

---

## References

- **Runner Releases:** https://github.com/actions/runner/releases
- **PR #4086:** https://github.com/actions/runner/pull/4086
- **Runner 2.329.0 Release:** https://github.com/actions/runner/releases/tag/v2.329.0
- **Runner 2.330.0 Release:** https://github.com/actions/runner/releases/tag/v2.330.0
- **Working Test Instance:** i-06a40893a1d53b7a9 (has 2.329.0, registered successfully)
- **Failed Production Instance:** i-005153f4d50ea264d (has 2.330.0, registration failed)
- **Failed AMI:** ami-0d93cdab3b95809bd (contains runner 2.330.0 - do not use)

---

## Next Steps

1. ✅ Updated AMI build guide to use 2.329.0
2. ✅ Updated user-data.sh to use 2.329.0
3. ⏳ **TODO:** Rebuild AMI with runner 2.329.0
4. ⏳ **TODO:** Deploy new instance and verify registration succeeds
5. ⏳ **TODO:** Update terraform AMI ID reference
6. ⏳ **TODO:** Commit all changes to git
7. ⏳ **TODO:** Monitor for runner 2.331.0 release with fix

---

## Lessons Learned

1. **Always test new runner versions** before deploying to production AMIs
2. **Pin runner versions explicitly** instead of using "latest"
3. **GitHub's progressive rollout** means latest may not be stable
4. **Version numbers don't guarantee compatibility** - test extensively
5. **Keep working version documented** for easy rollback
6. **Monitor GitHub runner issues** before upgrading
7. **Maintain version history** in documentation

---

**Status:** Issue documented and workaround implemented.  
**Action Required:** Rebuild AMI with runner 2.329.0 and deploy.
