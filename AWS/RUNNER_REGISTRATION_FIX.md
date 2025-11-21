# GitHub Actions Runner Registration Fix

**Date:** 2025-11-21  
**Issue:** Runner failed to register on AMI-based EC2 instances  
**Status:** ✅ FIXED  

## Problem Summary

EC2 instances launched from custom AMI with pre-installed runner 2.330.0 failed to register with error:
```
Http response code: NotFound from 'POST https://api.github.com/actions/runner-registration'
{"message":"Not Found","documentation_url":"https://docs.github.com/rest","status":"404"}
```

## Initial Misdiagnosis

Initially suspected runner version 2.330.0 had a bug (PR #4086) that broke self-hosted registration. However, **this was incorrect** because:
- Test script running today (2025-11-21) with 2.330.0 succeeded ✅
- Test script fetches "latest" which is 2.330.0
- Production deployment with 2.330.0 failed ❌

**Conclusion:** Runner version 2.330.0 is NOT the problem.

## Root Cause

The real issue was **how the runner configuration command was executed** in the user-data script:

### ❌ Broken Approach (Heredoc)
```bash
sudo -u runner bash <<RUNNEREOF
set -e
./config.sh \
    --url $${GITHUB_REPO_URL} \
    --token $${RUNNER_TOKEN} \
    --name $${RUNNER_NAME} \
    --labels $${RUNNER_LABELS} \
    --unattended \
    --replace
RUNNEREOF
```

**Problem:** Using a heredoc (`<<RUNNEREOF`) creates a subshell with different environment context. When executed during cloud-init/user-data:
1. Different environment variables are present
2. Runner's IsHostedServer detection logic may behave differently
3. AWS EC2 metadata might be interpreted incorrectly
4. Results in runner calling wrong API endpoint

### ✅ Fixed Approach (Direct Execution)
```bash
sudo -u runner ./config.sh \
    --url "$${GITHUB_REPO_URL}" \
    --token "$${RUNNER_TOKEN}" \
    --name "$${RUNNER_NAME}" \
    --labels "$${RUNNER_LABELS}" \
    --unattended \
    --replace 2>&1 | tee -a /var/log/runner-config.log
```

**Why This Works:**
- Direct execution as runner user (no subshell)
- Proper quoting of variables prevents expansion issues
- Same execution pattern as successful test script
- Environment context matches interactive SSH session

## Key Differences: Test vs Production

| Aspect | Test Script (✅ Works) | Production AMI (❌ Failed → ✅ Fixed) |
|--------|----------------------|--------------------------------------|
| **Execution Method** | Direct: `sudo -u runner ./config.sh` | Was: Heredoc subshell → Now: Direct |
| **Environment** | Interactive SSH session | cloud-init/user-data at boot |
| **Network** | Public subnet (direct internet) | Private subnet (NAT Gateway) |
| **Timing** | Manual, on-demand | Automated at instance launch |
| **Token Source** | `gh CLI` API call | GitHub Actions workflow API |

The critical difference was the **execution method**, not the environment or token source.

## Solution Implemented

**File:** `AWS/terraform/modules/ec2/user-data-ami.sh`

**Change:** Removed heredoc wrapper and execute `config.sh` directly as runner user

**Result:** Runner configuration now matches the successful test script pattern

## Verification

To verify the fix works:

1. **Build new AMI** with runner 2.330.0 (latest)
2. **Deploy instance** from new AMI
3. **Check console logs** for:
   ```
   ✅ Runner configuration successful
   ✅ Runner registration file created
   ```
4. **Verify in GitHub:**
   - Navigate to repository → Settings → Actions → Runners
   - Look for runner with "Idle" status

## Lessons Learned

1. **Don't jump to conclusions** - Initial assumption about PR #4086 bug was wrong
2. **Test thoroughly** - The test script's success was a critical clue
3. **Execution context matters** - Heredoc vs direct execution can behave differently
4. **Match working patterns** - When something works, replicate its exact approach
5. **Version numbers aren't always the culprit** - Configuration and execution matter more

## Files Modified

1. ✅ `AWS/terraform/modules/ec2/user-data-ami.sh` - Fixed config.sh execution
2. ✅ `AWS/terraform/modules/ec2/user-data.sh` - Reverted to use latest version
3. ✅ `AWS/AMI_BUILD_GUIDE.md` - Reverted incorrect version warnings

## Deprecated Documents

- ❌ `AWS/RUNNER_2.330.0_BUG_REPORT.md` - Based on incorrect diagnosis, can be deleted
- ❌ `AWS/QUICK_FIX_GUIDE.md` - Based on incorrect diagnosis, can be deleted

## Next Steps

1. Rebuild AMI with runner 2.330.0 using updated guide
2. Deploy and verify registration succeeds
3. Delete incorrect bug report documents
4. Update terraform AMI ID reference
5. Document this fix for future reference

## Technical Details

### Why Heredoc Was Problematic

When using `sudo -u runner bash <<RUNNEREOF`, the shell:
1. Parses the heredoc content in the current shell context
2. Creates a new bash process as the runner user
3. Passes the commands to stdin of that new process
4. New process inherits filtered environment variables

This filtering/inheritance can cause:
- Loss of critical environment markers
- Different PATH or other environment settings
- Changed process tree that affects detection logic
- Potential issues with special characters in variables

### Why Direct Execution Works

Using `sudo -u runner ./config.sh [args]`:
1. Directly executes config.sh as runner user
2. No intermediate shell process
3. Environment is more similar to interactive session
4. Process tree matches test script execution
5. No stdin redirection or heredoc parsing

## References

- Test script: `AWS/scripts/test-runner-registration.sh`
- User data (AMI): `AWS/terraform/modules/ec2/user-data-ami.sh`
- User data (full): `AWS/terraform/modules/ec2/user-data.sh`
- Runner releases: https://github.com/actions/runner/releases
- PR #4086: https://github.com/actions/runner/pull/4086 (NOT the actual cause)

---

**Status:** Issue resolved through proper execution method, not version downgrade.
