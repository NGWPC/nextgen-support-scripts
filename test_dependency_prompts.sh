#!/bin/bash
# Test script to verify dependency prompts in build_cluster.sh
# This runs the script in dry-run mode to check prompts without building

echo "=========================================="
echo "Test 1: Feature build with ngen"
echo "=========================================="
echo "Expected: Should prompt for ngen-forcing tag"
echo ""
echo "Run: ./parallel_works_scripts/build_cluster.sh --build-type=feature ngen"
echo ""

echo "=========================================="
echo "Test 2: Feature build with nwm-verf"
echo "=========================================="
echo "Expected: Should prompt for nwm-eval-mgr branch"
echo ""
echo "Run: ./parallel_works_scripts/build_cluster.sh --build-type=feature nwm-verf"
echo ""

echo "=========================================="
echo "Test 3: Release build with ngen"
echo "=========================================="
echo "Expected: Should prompt for both ngen tag AND ngen-forcing tag"
echo ""
echo "Run: ./parallel_works_scripts/build_cluster.sh --build-type=release ngen"
echo ""

echo "=========================================="
echo "Test 4: Release build with nwm-verf"
echo "=========================================="
echo "Expected: Should prompt for nwm-verf tag AND nwm-eval-mgr tag"
echo ""
echo "Run: ./parallel_works_scripts/build_cluster.sh --build-type=release nwm-verf"
echo ""

echo "=========================================="
echo "Test 5: Development build with all"
echo "=========================================="
echo "Expected: Should NOT prompt for any dependency tags (uses 'latest'/'development')"
echo ""
echo "Run: ./parallel_works_scripts/build_cluster.sh --build-type=development all"
echo ""
