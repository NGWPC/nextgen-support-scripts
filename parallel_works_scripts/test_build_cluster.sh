#!/bin/bash

# ==============================================================================
# Test Script for build_cluster.sh
# ==============================================================================
# This script runs integration tests to verify build_cluster.sh behavior:
# - Build order (dependencies built first)
# - Correct dependency tags used in builds
# - Feature builds use branch names, not "feature"
# - No unwanted prompts
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed
# ==============================================================================

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="${SCRIPT_DIR}/build_cluster.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0
TEST_OUTPUT_DIR="/tmp/build_cluster_tests_$(date +%s)"
mkdir -p "$TEST_OUTPUT_DIR"

# Estimated test durations in seconds
# These are conservative estimates based on typical build times
TEST1_DURATION=2400  # 40 minutes - fresh dev build with dependencies
TEST2_DURATION=300   # 5 minutes - reuses cached builds from Test 1
TEST3_DURATION=2700  # 45 minutes - release build with --no-cache
TEST4_DURATION=300   # 5 minutes - reuses some builds from Test 3
TEST5_DURATION=1500  # 25 minutes - feature build with ngen
TEST6_DURATION=300   # 5 minutes - reuses cached builds from Test 5

# Print test header with estimated duration
print_test_header() {
    local test_num="$1"
    local test_name="$2"
    local duration_seconds="$3"

    local start_time=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    echo -e "\n${BOLD}Running Test ${test_num}: ${test_name}${NC}"
    echo -e "  Started: ${start_time}"
    echo -e "  Estimated duration: ~$((duration_seconds / 60)) minutes"
}

# Print test result
print_result() {
    local test_name="$1"
    local result="$2"
    local details="$3"

    if [[ "$result" == "PASS" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        if [[ -n "$details" ]]; then
            echo -e "  ${YELLOW}Details:${NC} $details"
        fi
        ((TESTS_FAILED++))
    fi
}

# Verify build order in output
get_build_line_number() {
    local output_file="$1"
    local repo="$2"

    local line
    if [[ "$repo" == "ngen-forcing" ]]; then
        line=$(grep -n "Building ngen-bmi-forcing " "$output_file" 2>/dev/null | head -1)
    else
        line=$(grep -n "Building ${repo} " "$output_file" 2>/dev/null | head -1)
    fi

    [[ -n "$line" ]] && echo "${line%%:*}"
}

verify_build_order() {
    local output_file="$1"
    local expected_order=("$@")
    unset 'expected_order[0]'  # remove first element (output_file)

    local line_numbers=()
    for repo in "${expected_order[@]}"; do
        local line_num
        line_num=$(get_build_line_number "$output_file" "$repo")
        if [[ -z "$line_num" ]]; then
            echo "ERROR: Could not find build for $repo"
            return 1
        fi
        line_numbers+=("$line_num:$repo")
    done

    # Print found line numbers
    echo "  Build order found at lines: ${line_numbers[*]}"

    # Sort by line number and verify order
    local sorted_repos=($(printf '%s\n' "${line_numbers[@]}" | sort -n | cut -d: -f2))

    # Convert expected_order to 0-indexed array for comparison
    local expected_array=("${expected_order[@]}")

    for i in "${!expected_array[@]}"; do
        if [[ "${expected_array[$i]}" != "${sorted_repos[$i]}" ]]; then
            echo "ERROR: Expected ${expected_array[$i]} but found ${sorted_repos[$i]} at position $i"
            return 1
        fi
    done

    return 0
}

# Verify build argument used
verify_build_arg() {
    local output_file="$1"
    local repo="$2"
    local arg_name="$3"
    local expected_value="$4"

    local line_num
    line_num=$(get_build_line_number "$output_file" "$repo")
    if [[ -z "$line_num" ]]; then
        echo "ERROR: Could not find build line for $repo while checking ${arg_name}"
        return 1
    fi

    local line_text
    line_text=$(sed -n "${line_num}p" "$output_file")
    local actual_value=""
    if [[ "$line_text" =~ ${arg_name}=([^[:space:]]+) ]]; then
        actual_value="${BASH_REMATCH[1]}"
    fi

    if [[ "$actual_value" != "$expected_value" ]]; then
        echo "ERROR: Expected ${arg_name}=${expected_value} but found ${arg_name}=${actual_value}"
        return 1
    fi

    echo "  Found ${arg_name}=${actual_value} at line ${line_num}"
    return 0
}

# Verify no prompts in output
verify_no_prompt() {
    local output_file="$1"
    local prompt_text="$2"

    if grep -q "$prompt_text" "$output_file" 2>/dev/null; then
        echo "ERROR: Found unwanted prompt: $prompt_text"
        return 1
    fi

    return 0
}

# ==============================================================================
# TEST 1: Development build with nwm-cal-mgr
# ==============================================================================
print_test_header "1" "Development build with nwm-cal-mgr" "$TEST1_DURATION"
TEST1_OUTPUT="${TEST_OUTPUT_DIR}/test1_dev_cal_mgr.log"

if ! "$BUILD_SCRIPT" --build-type=development nwm-cal-mgr ngen > "$TEST1_OUTPUT" 2>&1; then
    print_result "Test 1: Development build (nwm-cal-mgr) - execution" "FAIL" "Build script failed"
else
    print_result "Test 1: Development build (nwm-cal-mgr) - execution" "PASS"

    # Verify build order: ngen-forcing -> ngen -> nwm-cal-mgr
    if verify_build_order "$TEST1_OUTPUT" "ngen-forcing" "ngen" "nwm-cal-mgr"; then
        print_result "Test 1: Build order (forcing->ngen->cal-mgr)" "PASS"
    else
        print_result "Test 1: Build order (forcing->ngen->cal-mgr)" "FAIL" "Incorrect build order"
    fi

    # Verify ngen uses ngen-forcing:latest
    if verify_build_arg "$TEST1_OUTPUT" "ngen" "NGEN_FORCING_TAG" "latest"; then
        print_result "Test 1: ngen uses NGEN_FORCING_TAG=latest" "PASS"
    else
        print_result "Test 1: ngen uses NGEN_FORCING_TAG=latest" "FAIL" "Wrong tag used"
    fi

    # Verify nwm-cal-mgr uses ngen:latest
    if verify_build_arg "$TEST1_OUTPUT" "nwm-cal-mgr" "NGEN_IMAGE_TAG" "latest"; then
        print_result "Test 1: nwm-cal-mgr uses NGEN_IMAGE_TAG=latest" "PASS"
    else
        print_result "Test 1: nwm-cal-mgr uses NGEN_IMAGE_TAG=latest" "FAIL" "Wrong tag used"
    fi

    # Verify no unwanted prompts
    if verify_no_prompt "$TEST1_OUTPUT" "Which.*Docker image tag"; then
        print_result "Test 1: No unwanted tag prompts" "PASS"
    else
        print_result "Test 1: No unwanted tag prompts" "FAIL" "Found unwanted prompt"
    fi
fi

# ==============================================================================
# TEST 2: Development build with nwm-fcst-mgr
# ==============================================================================
print_test_header "2" "Development build with nwm-fcst-mgr" "$TEST2_DURATION"
TEST2_OUTPUT="${TEST_OUTPUT_DIR}/test2_dev_fcst_mgr.log"

if ! "$BUILD_SCRIPT" --build-type=development nwm-fcst-mgr ngen > "$TEST2_OUTPUT" 2>&1; then
    print_result "Test 2: Development build (nwm-fcst-mgr) - execution" "FAIL" "Build script failed"
else
    print_result "Test 2: Development build (nwm-fcst-mgr) - execution" "PASS"

    # Verify build order: ngen-forcing -> ngen -> nwm-fcst-mgr
    if verify_build_order "$TEST2_OUTPUT" "ngen-forcing" "ngen" "nwm-fcst-mgr"; then
        print_result "Test 2: Build order (forcing->ngen->fcst-mgr)" "PASS"
    else
        print_result "Test 2: Build order (forcing->ngen->fcst-mgr)" "FAIL" "Incorrect build order"
    fi

    # Verify ngen uses ngen-forcing:latest
    if verify_build_arg "$TEST2_OUTPUT" "ngen" "NGEN_FORCING_TAG" "latest"; then
        print_result "Test 2: ngen uses NGEN_FORCING_TAG=latest" "PASS"
    else
        print_result "Test 2: ngen uses NGEN_FORCING_TAG=latest" "FAIL" "Wrong tag used"
    fi

    # Verify nwm-fcst-mgr uses ngen:latest
    if verify_build_arg "$TEST2_OUTPUT" "nwm-fcst-mgr" "NGEN_IMAGE_TAG" "latest"; then
        print_result "Test 2: nwm-fcst-mgr uses NGEN_IMAGE_TAG=latest" "PASS"
    else
        print_result "Test 2: nwm-fcst-mgr uses NGEN_IMAGE_TAG=latest" "FAIL" "Wrong tag used"
    fi

    # Verify no unwanted prompts
    if verify_no_prompt "$TEST2_OUTPUT" "Which.*Docker image tag"; then
        print_result "Test 2: No unwanted tag prompts" "PASS"
    else
        print_result "Test 2: No unwanted tag prompts" "FAIL" "Found unwanted prompt"
    fi
fi

# ==============================================================================
# TEST 3: Release build with nwm-cal-mgr
# ==============================================================================
print_test_header "3" "Release build with nwm-cal-mgr" "$TEST3_DURATION"
TEST3_OUTPUT="${TEST_OUTPUT_DIR}/test3_release_cal_mgr.log"

# Use echo to provide tag inputs non-interactively
(
    echo "v1.0.0"  # ngen-forcing tag
    echo "v2.0.0"  # ngen tag
    echo "v3.0.0"  # nwm-cal-mgr tag
) | "$BUILD_SCRIPT" --build-type=release --source-default=build nwm-cal-mgr ngen > "$TEST3_OUTPUT" 2>&1

if [[ ${PIPESTATUS[1]} -ne 0 ]]; then
    print_result "Test 3: Release build (nwm-cal-mgr) - execution" "FAIL" "Build script failed"
else
    print_result "Test 3: Release build (nwm-cal-mgr) - execution" "PASS"

    # Verify build order
    if verify_build_order "$TEST3_OUTPUT" "ngen-forcing" "ngen" "nwm-cal-mgr"; then
        print_result "Test 3: Build order (forcing->ngen->cal-mgr)" "PASS"
    else
        print_result "Test 3: Build order (forcing->ngen->cal-mgr)" "FAIL" "Incorrect build order"
    fi

    # Verify ngen uses ngen-forcing release tag
    if verify_build_arg "$TEST3_OUTPUT" "ngen" "NGEN_FORCING_TAG" "v1.0.0"; then
        print_result "Test 3: ngen uses NGEN_FORCING_TAG=v1.0.0" "PASS"
    else
        print_result "Test 3: ngen uses NGEN_FORCING_TAG=v1.0.0" "FAIL" "Wrong tag used"
    fi

    # Verify nwm-cal-mgr uses ngen release tag
    if verify_build_arg "$TEST3_OUTPUT" "nwm-cal-mgr" "NGEN_IMAGE_TAG" "v2.0.0"; then
        print_result "Test 3: nwm-cal-mgr uses NGEN_IMAGE_TAG=v2.0.0" "PASS"
    else
        print_result "Test 3: nwm-cal-mgr uses NGEN_IMAGE_TAG=v2.0.0" "FAIL" "Wrong tag used"
    fi

    # Verify no unwanted prompts
    if verify_no_prompt "$TEST3_OUTPUT" "Which.*Docker image tag"; then
        print_result "Test 3: No unwanted tag prompts" "PASS"
    else
        print_result "Test 3: No unwanted tag prompts" "FAIL" "Found unwanted prompt"
    fi
fi

# ==============================================================================
# TEST 4: Release build with nwm-fcst-mgr
# ==============================================================================
print_test_header "4" "Release build with nwm-fcst-mgr" "$TEST4_DURATION"
TEST4_OUTPUT="${TEST_OUTPUT_DIR}/test4_release_fcst_mgr.log"

(
    echo "v1.0.0"  # ngen-forcing tag
    echo "v2.0.0"  # ngen tag
    echo "v4.0.0"  # nwm-fcst-mgr tag
) | "$BUILD_SCRIPT" --build-type=release --source-default=build nwm-fcst-mgr ngen > "$TEST4_OUTPUT" 2>&1

if [[ ${PIPESTATUS[1]} -ne 0 ]]; then
    print_result "Test 4: Release build (nwm-fcst-mgr) - execution" "FAIL" "Build script failed"
else
    print_result "Test 4: Release build (nwm-fcst-mgr) - execution" "PASS"

    # Verify build order
    if verify_build_order "$TEST4_OUTPUT" "ngen-forcing" "ngen" "nwm-fcst-mgr"; then
        print_result "Test 4: Build order (forcing->ngen->fcst-mgr)" "PASS"
    else
        print_result "Test 4: Build order (forcing->ngen->fcst-mgr)" "FAIL" "Incorrect build order"
    fi

    # Verify ngen uses ngen-forcing release tag
    if verify_build_arg "$TEST4_OUTPUT" "ngen" "NGEN_FORCING_TAG" "v1.0.0"; then
        print_result "Test 4: ngen uses NGEN_FORCING_TAG=v1.0.0" "PASS"
    else
        print_result "Test 4: ngen uses NGEN_FORCING_TAG=v1.0.0" "FAIL" "Wrong tag used"
    fi

    # Verify nwm-fcst-mgr uses ngen release tag
    if verify_build_arg "$TEST4_OUTPUT" "nwm-fcst-mgr" "NGEN_IMAGE_TAG" "v2.0.0"; then
        print_result "Test 4: nwm-fcst-mgr uses NGEN_IMAGE_TAG=v2.0.0" "PASS"
    else
        print_result "Test 4: nwm-fcst-mgr uses NGEN_IMAGE_TAG=v2.0.0" "FAIL" "Wrong tag used"
    fi

    # Verify no unwanted prompts
    if verify_no_prompt "$TEST4_OUTPUT" "Which.*Docker image tag"; then
        print_result "Test 4: No unwanted tag prompts" "PASS"
    else
        print_result "Test 4: No unwanted tag prompts" "FAIL" "Found unwanted prompt"
    fi
fi

# ==============================================================================
# TEST 5: Feature build with ngen
# ==============================================================================
print_test_header "5" "Feature build with ngen" "$TEST5_DURATION"
TEST5_OUTPUT="${TEST_OUTPUT_DIR}/test5_feature_ngen.log"

(
    echo "feature/my-test-branch"     # ngen branch
    echo "feature/forcing-branch"     # ngen-forcing branch (dependency)
) | "$BUILD_SCRIPT" --build-type=feature ngen > "$TEST5_OUTPUT" 2>&1

if [[ ${PIPESTATUS[1]} -ne 0 ]]; then
    print_result "Test 5: Feature build (ngen) - execution" "FAIL" "Build script failed"
else
    print_result "Test 5: Feature build (ngen) - execution" "PASS"

    # Verify branch name used in Docker tag (not "feature")
    if grep -q "ngen-bmi-forcing:feature/forcing-branch\|ngen-bmi-forcing:feature-forcing-branch" "$TEST5_OUTPUT"; then
        print_result "Test 5: ngen-forcing uses branch name in tag" "PASS"
    else
        print_result "Test 5: ngen-forcing uses branch name in tag" "FAIL" "Not using branch name"
    fi

    if grep -q "ngen:feature/my-test-branch\|ngen:feature-my-test-branch" "$TEST5_OUTPUT"; then
        print_result "Test 5: ngen uses branch name in tag" "PASS"
    else
        print_result "Test 5: ngen uses branch name in tag" "FAIL" "Not using branch name"
    fi

    # Verify not using generic "feature" tag
    if ! grep -q "ngen:feature[^/]" "$TEST5_OUTPUT"; then
        print_result "Test 5: Not using generic 'feature' tag" "PASS"
    else
        print_result "Test 5: Not using generic 'feature' tag" "FAIL" "Found generic feature tag"
    fi

    # Verify all builds are local (no pulling)
    if ! grep -q "Pulling.*Docker image" "$TEST5_OUTPUT"; then
        print_result "Test 5: All images built locally (no pulling)" "PASS"
    else
        print_result "Test 5: All images built locally (no pulling)" "FAIL" "Found pull operation"
    fi

    # Verify no prompts about image source (build/pull)
    if ! grep -q "Image source for.*\[build/pull\]" "$TEST5_OUTPUT"; then
        print_result "Test 5: No image source prompts" "PASS"
    else
        print_result "Test 5: No image source prompts" "FAIL" "Found image source prompt"
    fi

    # Verify no default branch prompts
    if ! grep -q "default.*development\|default.*main" "$TEST5_OUTPUT"; then
        print_result "Test 5: No default branch in prompts" "PASS"
    else
        print_result "Test 5: No default branch in prompts" "FAIL" "Found default branch reference"
    fi

    # Verify no unwanted prompts
    if verify_no_prompt "$TEST5_OUTPUT" "Which.*Docker image tag"; then
        print_result "Test 5: No unwanted tag prompts" "PASS"
    else
        print_result "Test 5: No unwanted tag prompts" "FAIL" "Found unwanted prompt"
    fi
fi

# ==============================================================================
# TEST 6: Feature build with nwm-cal-mgr
# ==============================================================================
print_test_header "6" "Feature build with nwm-cal-mgr" "$TEST6_DURATION"
TEST6_OUTPUT="${TEST_OUTPUT_DIR}/test6_feature_cal_mgr.log"

(
    echo "feature/cal-mgr-branch"      # nwm-cal-mgr branch
    echo "feature/ngen-branch"         # ngen branch (dependency)
    echo "feature/forcing-branch"      # ngen-forcing branch (dependency)
) | "$BUILD_SCRIPT" --build-type=feature nwm-cal-mgr > "$TEST6_OUTPUT" 2>&1

if [[ ${PIPESTATUS[1]} -ne 0 ]]; then
    print_result "Test 6: Feature build (nwm-cal-mgr) - execution" "FAIL" "Build script failed"
else
    print_result "Test 6: Feature build (nwm-cal-mgr) - execution" "PASS"

    # Verify branch name used in Docker tag
    if grep -q "nwm-cal-mgr:feature/cal-mgr-branch\|nwm-cal-mgr:feature-cal-mgr-branch" "$TEST6_OUTPUT"; then
        print_result "Test 6: nwm-cal-mgr uses branch name in tag" "PASS"
    else
        print_result "Test 6: nwm-cal-mgr uses branch name in tag" "FAIL" "Not using branch name"
    fi

    # Verify not using generic "feature" tag
    if ! grep -q "nwm-cal-mgr:feature[^/]" "$TEST6_OUTPUT"; then
        print_result "Test 6: Not using generic 'feature' tag" "PASS"
    else
        print_result "Test 6: Not using generic 'feature' tag" "FAIL" "Found generic feature tag"
    fi

    # Verify all builds are local
    if ! grep -q "Pulling.*Docker image" "$TEST6_OUTPUT"; then
        print_result "Test 6: All images built locally (no pulling)" "PASS"
    else
        print_result "Test 6: All images built locally (no pulling)" "FAIL" "Found pull operation"
    fi

    # Verify no image source prompts
    if ! grep -q "Image source for.*\[build/pull\]" "$TEST6_OUTPUT"; then
        print_result "Test 6: No image source prompts" "PASS"
    else
        print_result "Test 6: No image source prompts" "FAIL" "Found image source prompt"
    fi

    # Verify no unwanted prompts
    if verify_no_prompt "$TEST6_OUTPUT" "Which.*Docker image tag"; then
        print_result "Test 6: No unwanted tag prompts" "PASS"
    else
        print_result "Test 6: No unwanted tag prompts" "FAIL" "Found unwanted prompt"
    fi
fi

# ==============================================================================
# SUMMARY
# ==============================================================================
echo -e "\n${BOLD}========================================${NC}"
echo -e "${BOLD}TEST SUMMARY${NC}"
echo -e "${BOLD}========================================${NC}"
echo -e "${GREEN}Passed:${NC} $TESTS_PASSED"
echo -e "${RED}Failed:${NC} $TESTS_FAILED"
echo -e "Total:  $((TESTS_PASSED + TESTS_FAILED))"
echo -e "\nTest outputs saved to: $TEST_OUTPUT_DIR"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}✓ ALL TESTS PASSED${NC}"
    exit 0
else
    echo -e "\n${RED}✗ SOME TESTS FAILED${NC}"
    echo -e "\nReview logs in $TEST_OUTPUT_DIR for details"
    exit 1
fi
