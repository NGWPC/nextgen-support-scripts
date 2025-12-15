# Implementation Plan: Improve Dependency Management in build_cluster.sh

## Overview
Update the build_cluster.sh script to ensure proper dependency handling across all build types (development, feature, release) with correct prompting for dependency tags/branches.

## Current State Analysis

### What Already Works ✅
1. **Build order**: `reorder_repos_by_dependency()` already ensures correct order:
   - ngen-forcing → ngen → nwm-cal-mgr/nwm-fcst-mgr
2. **Feature builds**: Already prompt for:
   - ngen-forcing tag when building ngen (line 469)
   - ngen tag when building nwm-cal-mgr/nwm-fcst-mgr (line 478)
3. **Release builds**: Already prompt for:
   - ngen tag when building nwm-cal-mgr/nwm-fcst-mgr (lines 558-567)
   - nwm-eval-mgr tag when building nwm-verf (line 571)
4. **Development builds**: Correctly hardcodes "latest" and "development" - no changes needed

### Issues Found ❌

#### Issue 1: Release builds - Missing ngen-forcing prompt
**Location**: Lines 551-555 (ngen tag prompt section)
**Problem**: When ngen is selected for release build, the script doesn't prompt for which ngen-forcing tag to use. It falls back to using the ngen tag (line 846).
**Impact**: Users can't specify a different ngen-forcing release tag than the ngen tag.

#### Issue 2: Feature builds - nwm-verf hardcodes dependency
**Location**: Line 1215 (feature build nwm-verf section)
**Problem**: `NWM_EVAL_MGR_TAG` is hardcoded to "feature" instead of using a DEPENDENCY_TAG
**Impact**: Users can't specify which nwm-eval-mgr tag to use for nwm-verf feature builds

#### Issue 3: prompt_dependency_tags() doesn't handle nwm-verf
**Location**: Lines 446-484 (prompt_dependency_tags function)
**Problem**: Function doesn't prompt for nwm-eval-mgr when nwm-verf is selected
**Impact**: Missing prompts for nwm-verf's dependency in feature builds

## Implementation Plan

### Change 1: Update Release Build Tag Prompts
**File**: build_cluster.sh, lines 551-555
**Action**: When ngen is selected, prompt for ngen-forcing tag
**Code location**: In the release tag prompts section

```bash
# Current:
ngen)
    if [[ -z "${TAGS[ngen]:-}" ]]; then
        read -p "Enter ngen tag: " TAGS[ngen]
    fi
;;

# New:
ngen)
    if [[ -z "${TAGS[ngen]:-}" ]]; then
        read -p "Enter ngen tag: " TAGS[ngen]
    fi
    if [[ -z "${TAGS[ngen-forcing]:-}" ]]; then
        read -p "Enter ngen-forcing tag (used by ngen): " TAGS[ngen-forcing]
    fi
;;
```

### Change 2: Update prompt_dependency_tags() Function
**File**: build_cluster.sh, lines 446-484
**Actions**:
1. Extend function to handle both feature AND release builds
2. Add nwm-verf dependency prompting

**Changes needed**:
- Remove line 450: `[[ "$build_type" != "feature" ]] && return 0`
- Replace with logic that handles both feature and release
- Add section to prompt for nwm-eval-mgr when nwm-verf is selected

```bash
# Add after line 483 (after mgr prompts):

# prompt for nwm-eval-mgr branch/tag if nwm-verf is selected
if [[ " ${SELECTED_REPOS[@]} " =~ " nwm-verf " ]]; then
    if [[ "$build_type" == "feature" ]]; then
        local default_branch="feature"
        if [[ -z "${DEPENDENCY_TAGS[nwm-verf]:-}" ]]; then
            read -p "Which nwm-eval-mgr branch do you want nwm-verf to use? (default: ${default_branch}): " ans
            DEPENDENCY_TAGS["nwm-verf"]="${ans:-$default_branch}"
        fi
    elif [[ "$build_type" == "release" ]]; then
        if [[ -z "${DEPENDENCY_TAGS[nwm-verf]:-}" ]]; then
            read -p "Which nwm-eval-mgr release tag do you want nwm-verf to use?: " ans
            DEPENDENCY_TAGS["nwm-verf"]="${ans}"
        fi
    fi
fi
```

### Change 3: Update Feature Build nwm-verf Section
**File**: build_cluster.sh, line 1215
**Action**: Use DEPENDENCY_TAG instead of hardcoded "feature"

```bash
# Current (line 1215):
--build-arg NWM_EVAL_MGR_TAG="feature" \

# New:
local nwm_eval_mgr_tag="${DEPENDENCY_TAGS[nwm-verf]:-feature}"
--build-arg NWM_EVAL_MGR_TAG="${nwm_eval_mgr_tag}" \
```

### Change 4: Update Release Build ngen Section
**File**: build_cluster.sh, line 846
**Action**: Don't fall back to TAGS[ngen] if ngen-forcing tag isn't set

```bash
# Current (line 846):
local forcing_tag="${TAGS[ngen-forcing]:-${TAGS[ngen]}}"

# New (ensure TAGS[ngen-forcing] is always set via prompts):
local forcing_tag="${TAGS[ngen-forcing]}"
```

Note: This depends on Change 1 ensuring TAGS[ngen-forcing] is always prompted when ngen is selected.

## Testing Plan

### Test Case 1: Release Build with ngen
```bash
./build_cluster.sh --build-type=release ngen
```
**Expected**: Should prompt for both ngen tag AND ngen-forcing tag

### Test Case 2: Feature Build with nwm-verf
```bash
./build_cluster.sh --build-type=feature nwm-verf
```
**Expected**: Should prompt for nwm-eval-mgr branch to use

### Test Case 3: Release Build with nwm-cal-mgr
```bash
./build_cluster.sh --build-type=release nwm-cal-mgr
```
**Expected**: Should prompt for nwm-cal-mgr tag AND ngen tag (existing behavior should still work)

### Test Case 4: Development Build (no changes)
```bash
./build_cluster.sh --build-type=development all
```
**Expected**: Should use "latest"/"development" tags with no prompts (existing behavior)

## Files to Modify
- `/home/christopher.nealen/nwm-automation-scripts/parallel_works_scripts/build_cluster.sh`

## Summary of Changes
1. ✏️ Update release build ngen tag prompt (lines 551-555) - add ngen-forcing prompt
2. ✏️ Update `prompt_dependency_tags()` function (lines 446-484) - extend to handle release and add nwm-verf
3. ✏️ Update feature build nwm-verf Docker build (line 1215) - use DEPENDENCY_TAG
4. ✏️ Update release build ngen Docker build (line 846) - remove fallback

## Risk Assessment
- **Low Risk**: Changes are additive (new prompts) and follow existing patterns
- **No Breaking Changes**: Development builds unchanged, existing release/feature behavior enhanced
- **Fallback Safety**: All new prompts have sensible defaults for feature builds
