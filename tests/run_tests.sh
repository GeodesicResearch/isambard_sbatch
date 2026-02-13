#!/bin/bash
# Test suite for isambard_sbatch
#
# Usage: bash tests/run_tests.sh
#
# Runs unit tests (parsing logic) and integration tests (real SLURM).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$SCRIPT_DIR/../bin"
ISAMBARD_SBATCH="$BIN_DIR/isambard_sbatch"
SBATCH_WRAPPER="$BIN_DIR/sbatch"
TMPDIR_TESTS=$(mktemp -d)

PASS=0
FAIL=0
SKIP=0

cleanup() {
    rm -rf "$TMPDIR_TESTS"
}
trap cleanup EXIT

# ─────────────────────────────────────────────────────────────────────────────
# Test helpers
# ─────────────────────────────────────────────────────────────────────────────

assert_eq() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $test_name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $test_name"
        echo "        expected: '$expected'"
        echo "        actual:   '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local test_name="$1"
    local needle="$2"
    local haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS: $test_name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $test_name"
        echo "        expected to contain: '$needle'"
        echo "        actual output: '$haystack'"
        FAIL=$((FAIL + 1))
    fi
}

assert_exit_code() {
    local test_name="$1"
    local expected_code="$2"
    local actual_code="$3"
    if [[ "$expected_code" == "$actual_code" ]]; then
        echo "  PASS: $test_name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $test_name"
        echo "        expected exit code: $expected_code"
        echo "        actual exit code:   $actual_code"
        FAIL=$((FAIL + 1))
    fi
}

skip_test() {
    local test_name="$1"
    local reason="$2"
    echo "  SKIP: $test_name ($reason)"
    SKIP=$((SKIP + 1))
}

# Source the isambard_sbatch script to get access to functions
source "$ISAMBARD_SBATCH" --source-only

# ─────────────────────────────────────────────────────────────────────────────
# Create test fixtures
# ─────────────────────────────────────────────────────────────────────────────

cat > "$TMPDIR_TESTS/nodes4.sbatch" << 'EOF'
#!/bin/bash
#SBATCH --job-name=test
#SBATCH --nodes=4
#SBATCH --time=01:00:00
hostname
EOF

cat > "$TMPDIR_TESTS/nodes16.sbatch" << 'EOF'
#!/bin/bash
#SBATCH -J test
#SBATCH -N 16
#SBATCH -t 01:00:00
hostname
EOF

cat > "$TMPDIR_TESTS/nodes8_compact.sbatch" << 'EOF'
#!/bin/bash
#SBATCH -N8
#SBATCH --time=01:00:00
hostname
EOF

cat > "$TMPDIR_TESTS/no_nodes.sbatch" << 'EOF'
#!/bin/bash
#SBATCH --job-name=test
#SBATCH --time=01:00:00
hostname
EOF

cat > "$TMPDIR_TESTS/node_range.sbatch" << 'EOF'
#!/bin/bash
#SBATCH --nodes=2-8
hostname
EOF

cat > "$TMPDIR_TESTS/multiple_node_directives.sbatch" << 'EOF'
#!/bin/bash
#SBATCH --nodes=4
#SBATCH --time=01:00:00
#SBATCH --nodes=16
hostname
EOF

cat > "$TMPDIR_TESTS/simple.sbatch" << 'EOF'
#!/bin/bash
#SBATCH --time=00:01:00
hostname
EOF

# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "                     ISAMBARD_SBATCH TEST SUITE"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
echo "── Unit Tests: parse_nodes_from_args ──"
# ─────────────────────────────────────────────────────────────────────────────

result=$(parse_nodes_from_args --nodes=4 script.sh)
assert_eq "--nodes=4" "4" "$result"

result=$(parse_nodes_from_args --nodes 8 script.sh)
assert_eq "--nodes 8" "8" "$result"

result=$(parse_nodes_from_args -N 16 script.sh)
assert_eq "-N 16" "16" "$result"

result=$(parse_nodes_from_args -N32 script.sh)
assert_eq "-N32" "32" "$result"

result=$(parse_nodes_from_args --job-name=test --nodes=64 --time=01:00:00 script.sh)
assert_eq "--nodes=64 among other opts" "64" "$result"

result=$(parse_nodes_from_args --time=01:00:00 script.sh)
assert_eq "no nodes in args" "" "$result"

result=$(parse_nodes_from_args)
assert_eq "empty args" "" "$result"

result=$(parse_nodes_from_args --wrap="hostname")
assert_eq "--wrap with no nodes" "" "$result"

result=$(parse_nodes_from_args --nodes=2 --nodes=8 script.sh)
assert_eq "last --nodes wins" "8" "$result"

result=$(parse_nodes_from_args -N 2-4 script.sh)
assert_eq "-N with range" "2-4" "$result"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Unit Tests: parse_nodes_from_script ──"
# ─────────────────────────────────────────────────────────────────────────────

result=$(parse_nodes_from_script "$TMPDIR_TESTS/nodes4.sbatch")
assert_eq "#SBATCH --nodes=4" "4" "$result"

result=$(parse_nodes_from_script "$TMPDIR_TESTS/nodes16.sbatch")
assert_eq "#SBATCH -N 16" "16" "$result"

result=$(parse_nodes_from_script "$TMPDIR_TESTS/nodes8_compact.sbatch")
assert_eq "#SBATCH -N8" "8" "$result"

result=$(parse_nodes_from_script "$TMPDIR_TESTS/no_nodes.sbatch")
assert_eq "no #SBATCH nodes" "" "$result"

result=$(parse_nodes_from_script "$TMPDIR_TESTS/node_range.sbatch")
assert_eq "#SBATCH --nodes=2-8" "2-8" "$result"

result=$(parse_nodes_from_script "$TMPDIR_TESTS/multiple_node_directives.sbatch")
assert_eq "last #SBATCH --nodes wins" "16" "$result"

result=$(parse_nodes_from_script "/nonexistent/file.sh")
assert_eq "nonexistent script" "" "$result"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Unit Tests: find_script_file ──"
# ─────────────────────────────────────────────────────────────────────────────

result=$(find_script_file --nodes=4 script.sh)
assert_eq "script after --nodes=4" "script.sh" "$result"

result=$(find_script_file --nodes 4 script.sh)
assert_eq "script after --nodes 4" "script.sh" "$result"

result=$(find_script_file -N 4 -J myname script.sh)
assert_eq "script after -N 4 -J myname" "script.sh" "$result"

result=$(find_script_file --time=01:00:00 --partition=workq script.sh arg1 arg2)
assert_eq "script with trailing args" "script.sh" "$result"

result=$(find_script_file --wrap="hostname")
assert_eq "--wrap with no script" "" "$result"

result=$(find_script_file -N4 -t 01:00:00 myjob.sbatch)
assert_eq "script after -N4 -t" "myjob.sbatch" "$result"

result=$(find_script_file --nodes=4 --dependency=afterok:12345 myscript.sh)
assert_eq "script after --dependency" "myscript.sh" "$result"

result=$(find_script_file -A brics.a5k -N 16 -d afterok:12345 train.sbatch)
assert_eq "script after -A -N -d" "train.sbatch" "$result"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Unit Tests: resolve_node_count ──"
# ─────────────────────────────────────────────────────────────────────────────

result=$(resolve_node_count "4")
assert_eq "plain number" "4" "$result"

result=$(resolve_node_count "2-8")
assert_eq "range 2-8" "8" "$result"

result=$(resolve_node_count "1-1")
assert_eq "range 1-1" "1" "$result"

result=$(resolve_node_count "4-64")
assert_eq "range 4-64" "64" "$result"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Unit Tests: Combined parsing (CLI overrides script) ──"
# ─────────────────────────────────────────────────────────────────────────────

# CLI specifies nodes — should use CLI value even if script has different value
cli_nodes=$(parse_nodes_from_args --nodes=2 "$TMPDIR_TESTS/nodes16.sbatch")
assert_eq "CLI --nodes=2 overrides script -N16" "2" "$cli_nodes"

# CLI does not specify — should fall back to script
cli_nodes=$(parse_nodes_from_args "$TMPDIR_TESTS/nodes4.sbatch")
if [[ -z "$cli_nodes" ]]; then
    script=$(find_script_file "$TMPDIR_TESTS/nodes4.sbatch")
    script_nodes=$(parse_nodes_from_script "$script")
    assert_eq "fallback to script (nodes=4)" "4" "$script_nodes"
else
    assert_eq "should not find nodes in args" "" "$cli_nodes"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Integration Tests: Dry Run ──"
# ─────────────────────────────────────────────────────────────────────────────

# Check if SLURM is available
if command -v squeue &>/dev/null; then
    # Get current a5k usage for context
    current=$(ISAMBARD_SBATCH_ACCOUNT=brics.a5k get_current_nodes)
    echo "  (Current brics.a5k node usage: $current)"

    # Test 1: Dry run that should PASS (high limit)
    output=$(ISAMBARD_SBATCH_MAX_NODES=9999 ISAMBARD_SBATCH_ACCOUNT=brics.a5k ISAMBARD_SBATCH_DRY_RUN=1 \
        "$ISAMBARD_SBATCH" --nodes=1 --wrap="hostname" 2>&1) || true
    assert_contains "dry run passes with high limit" "[DRY RUN] Would submit" "$output"

    # Test 2: Dry run that should be BLOCKED (limit=0)
    output=$(ISAMBARD_SBATCH_MAX_NODES=0 ISAMBARD_SBATCH_ACCOUNT=brics.a5k ISAMBARD_SBATCH_DRY_RUN=1 \
        "$ISAMBARD_SBATCH" --nodes=1 --wrap="hostname" 2>&1) || true
    assert_contains "blocked with limit=0" "BLOCKED" "$output"

    # Test 3: Dry run with limit = current usage (requesting 1 more should block)
    if [[ $current -gt 0 ]]; then
        output=$(ISAMBARD_SBATCH_MAX_NODES=$current ISAMBARD_SBATCH_ACCOUNT=brics.a5k ISAMBARD_SBATCH_DRY_RUN=1 \
            "$ISAMBARD_SBATCH" --nodes=1 --wrap="hostname" 2>&1) || true
        assert_contains "blocked when at capacity" "BLOCKED" "$output"
    else
        skip_test "blocked when at capacity" "no current jobs running"
    fi

    # Test 4: Dry run with limit = current + 1 (should pass)
    limit=$((current + 1))
    output=$(ISAMBARD_SBATCH_MAX_NODES=$limit ISAMBARD_SBATCH_ACCOUNT=brics.a5k ISAMBARD_SBATCH_DRY_RUN=1 \
        "$ISAMBARD_SBATCH" --nodes=1 --wrap="hostname" 2>&1) || true
    assert_contains "passes when 1 under limit" "[DRY RUN] Would submit" "$output"

    # Test 5: Dry run with --nodes from script (no CLI --nodes)
    output=$(ISAMBARD_SBATCH_MAX_NODES=9999 ISAMBARD_SBATCH_ACCOUNT=brics.a5k ISAMBARD_SBATCH_DRY_RUN=1 \
        "$ISAMBARD_SBATCH" "$TMPDIR_TESTS/nodes4.sbatch" 2>&1) || true
    assert_contains "dry run with script nodes" "[DRY RUN] Would submit" "$output"
    assert_contains "dry run reports +4 nodes" "+4 nodes" "$output"

    # Test 6: FORCE bypasses limit
    output=$(ISAMBARD_SBATCH_MAX_NODES=0 ISAMBARD_SBATCH_ACCOUNT=brics.a5k ISAMBARD_SBATCH_DRY_RUN=1 ISAMBARD_SBATCH_FORCE=1 \
        "$ISAMBARD_SBATCH" --nodes=64 --wrap="hostname" 2>&1) || true
    assert_contains "force bypasses limit" "[FORCED]" "$output"

    # Test 7: Default nodes (no --nodes anywhere) should be 1
    output=$(ISAMBARD_SBATCH_MAX_NODES=9999 ISAMBARD_SBATCH_ACCOUNT=brics.a5k ISAMBARD_SBATCH_DRY_RUN=1 \
        "$ISAMBARD_SBATCH" "$TMPDIR_TESTS/no_nodes.sbatch" 2>&1) || true
    assert_contains "default 1 node" "+1 nodes" "$output"

    # Test 8: Node range in script
    output=$(ISAMBARD_SBATCH_MAX_NODES=9999 ISAMBARD_SBATCH_ACCOUNT=brics.a5k ISAMBARD_SBATCH_DRY_RUN=1 \
        "$ISAMBARD_SBATCH" "$TMPDIR_TESTS/node_range.sbatch" 2>&1) || true
    assert_contains "node range resolves to max (8)" "+8 nodes" "$output"

    # Test 9: Blocked output includes account name
    output=$(ISAMBARD_SBATCH_MAX_NODES=0 ISAMBARD_SBATCH_ACCOUNT=brics.a5k ISAMBARD_SBATCH_DRY_RUN=1 \
        "$ISAMBARD_SBATCH" --nodes=1 --wrap="hostname" 2>&1) || true
    assert_contains "blocked msg shows account" "brics.a5k" "$output"

    # Test 10: Blocked exit code is 1
    set +e
    ISAMBARD_SBATCH_MAX_NODES=0 ISAMBARD_SBATCH_ACCOUNT=brics.a5k ISAMBARD_SBATCH_DRY_RUN=1 \
        "$ISAMBARD_SBATCH" --nodes=1 --wrap="hostname" &>/dev/null
    code=$?
    set -e
    assert_exit_code "blocked exit code is 1" "1" "$code"

    # Test 11: Cluster summary appears on passing dry run
    output=$(ISAMBARD_SBATCH_MAX_NODES=9999 ISAMBARD_SBATCH_ACCOUNT=brics.a5k ISAMBARD_SBATCH_DRY_RUN=1 \
        "$ISAMBARD_SBATCH" --nodes=1 --wrap="hostname" 2>&1) || true
    assert_contains "summary shows cluster stats" "Cluster:" "$output"
    assert_contains "summary shows account usage" "Account:" "$output"
    assert_contains "summary shows headroom" "headroom:" "$output"
    assert_contains "summary shows request line" "Request:" "$output"

    # Test 12: Cluster summary appears on blocked submission too
    output=$(ISAMBARD_SBATCH_MAX_NODES=0 ISAMBARD_SBATCH_ACCOUNT=brics.a5k ISAMBARD_SBATCH_DRY_RUN=1 \
        "$ISAMBARD_SBATCH" --nodes=1 --wrap="hostname" 2>&1) || true
    assert_contains "blocked output includes cluster stats" "Cluster:" "$output"
    assert_contains "blocked output includes per-user breakdown" "$USER" "$output"

else
    skip_test "all integration tests" "squeue not found (not on SLURM cluster)"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Integration Tests: sbatch Wrapper ──"
# ─────────────────────────────────────────────────────────────────────────────

if [[ -x "$SBATCH_WRAPPER" ]]; then
    # The sbatch wrapper should invoke isambard_sbatch
    output=$(ISAMBARD_SBATCH_MAX_NODES=9999 ISAMBARD_SBATCH_ACCOUNT=brics.a5k ISAMBARD_SBATCH_DRY_RUN=1 \
        "$SBATCH_WRAPPER" --nodes=1 --wrap="hostname" 2>&1) || true
    assert_contains "sbatch wrapper delegates to isambard_sbatch" "[DRY RUN]" "$output"

    # sbatch wrapper should also block
    set +e
    ISAMBARD_SBATCH_MAX_NODES=0 ISAMBARD_SBATCH_ACCOUNT=brics.a5k ISAMBARD_SBATCH_DRY_RUN=1 \
        "$SBATCH_WRAPPER" --nodes=1 --wrap="hostname" &>/dev/null
    code=$?
    set -e
    assert_exit_code "sbatch wrapper blocks when over limit" "1" "$code"
else
    skip_test "sbatch wrapper tests" "wrapper not found at $SBATCH_WRAPPER"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Integration Tests: Real Submission (ISAMBARD_SBATCH_MAX_NODES=2) ──"
# ─────────────────────────────────────────────────────────────────────────────

if command -v squeue &>/dev/null; then
    current=$(ISAMBARD_SBATCH_ACCOUNT=brics.a5k get_current_nodes)

    # Test: With ISAMBARD_SBATCH_MAX_NODES=2, check if we can submit 1 node
    if [[ $((current + 1)) -le 2 ]]; then
        # Should succeed — actually submit a tiny job
        output=$(ISAMBARD_SBATCH_MAX_NODES=2 ISAMBARD_SBATCH_ACCOUNT=brics.a5k \
            "$ISAMBARD_SBATCH" --nodes=1 --time=00:01:00 --wrap="echo isambard_sbatch_test" 2>&1)
        code=$?
        if [[ $code -eq 0 ]] && [[ "$output" =~ [0-9]+ ]]; then
            # Extract job ID and cancel it
            job_id=$(echo "$output" | grep -oP '[0-9]+' | tail -1)
            echo "  PASS: real submission succeeded (job $job_id)"
            PASS=$((PASS + 1))
            # Clean up
            scancel "$job_id" 2>/dev/null || true
            echo "  (cancelled test job $job_id)"
        else
            echo "  FAIL: real submission should have succeeded"
            echo "        exit code: $code"
            echo "        output: $output"
            FAIL=$((FAIL + 1))
        fi
    else
        skip_test "real submission under limit" "current usage ($current) + 1 > 2"
    fi

    # Test: With ISAMBARD_SBATCH_MAX_NODES=2, requesting nodes that exceed limit
    exceed_nodes=$((2 - current + 1))
    if [[ $exceed_nodes -gt 0 ]]; then
        set +e
        output=$(ISAMBARD_SBATCH_MAX_NODES=2 ISAMBARD_SBATCH_ACCOUNT=brics.a5k \
            "$ISAMBARD_SBATCH" --nodes=$exceed_nodes --time=00:01:00 --wrap="echo blocked" 2>&1)
        code=$?
        set -e
        if [[ $code -eq 1 ]] && [[ "$output" == *"BLOCKED"* ]]; then
            echo "  PASS: real submission correctly blocked ($exceed_nodes nodes over limit)"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: real submission should have been blocked"
            echo "        exit code: $code"
            echo "        output: $output"
            FAIL=$((FAIL + 1))
        fi
    else
        skip_test "real submission over limit" "can't construct exceeding request"
    fi
else
    skip_test "real submission tests" "squeue not found"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Integration Tests: --check Mode ──"
# ─────────────────────────────────────────────────────────────────────────────

if command -v squeue &>/dev/null; then
    # Test 1: --check returns 0 when under limit
    set +e
    output=$(ISAMBARD_SBATCH_MAX_NODES=9999 ISAMBARD_SBATCH_ACCOUNT=brics.a5k \
        "$ISAMBARD_SBATCH" --check 2>&1)
    code=$?
    set -e
    assert_exit_code "--check returns 0 under limit" "0" "$code"
    assert_contains "--check output shows OK" "OK" "$output"
    assert_contains "--check output shows account" "brics.a5k" "$output"

    # Test 2: --check returns 1 when over limit
    set +e
    output=$(ISAMBARD_SBATCH_MAX_NODES=0 ISAMBARD_SBATCH_ACCOUNT=brics.a5k \
        "$ISAMBARD_SBATCH" --check 2>&1)
    code=$?
    set -e
    assert_exit_code "--check returns 1 over limit" "1" "$code"
    assert_contains "--check blocked output shows BLOCKED" "BLOCKED" "$output"

    # Test 3: --check with FORCE=1 returns 0 even when over limit
    set +e
    output=$(ISAMBARD_SBATCH_MAX_NODES=0 ISAMBARD_SBATCH_ACCOUNT=brics.a5k ISAMBARD_SBATCH_FORCE=1 \
        "$ISAMBARD_SBATCH" --check 2>&1)
    code=$?
    set -e
    assert_exit_code "--check with FORCE returns 0" "0" "$code"
    assert_contains "--check forced output shows OK" "OK" "$output"

    # Test 4: --check ignores DISABLED (still blocks when DISABLED=1)
    set +e
    output=$(ISAMBARD_SBATCH_MAX_NODES=0 ISAMBARD_SBATCH_ACCOUNT=brics.a5k ISAMBARD_SBATCH_DISABLED=1 \
        "$ISAMBARD_SBATCH" --check 2>&1)
    code=$?
    set -e
    assert_exit_code "--check ignores DISABLED (still blocks)" "1" "$code"
    assert_contains "--check with DISABLED still shows BLOCKED" "BLOCKED" "$output"

    # Test 5: --check does not invoke sbatch (output should not contain "Submitted batch job")
    set +e
    output=$(ISAMBARD_SBATCH_MAX_NODES=9999 ISAMBARD_SBATCH_ACCOUNT=brics.a5k \
        "$ISAMBARD_SBATCH" --check 2>&1)
    set -e
    if [[ "$output" == *"Submitted batch job"* ]]; then
        echo "  FAIL: --check should not invoke sbatch"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: --check does not invoke sbatch"
        PASS=$((PASS + 1))
    fi
else
    skip_test "--check mode tests" "squeue not found (not on SLURM cluster)"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Integration Tests: DISABLED mode ──"
# ─────────────────────────────────────────────────────────────────────────────

if command -v squeue &>/dev/null; then
    # When disabled, should pass straight through (use --wrap to keep it harmless)
    output=$(ISAMBARD_SBATCH_DISABLED=1 ISAMBARD_SBATCH_MAX_NODES=0 \
        "$ISAMBARD_SBATCH" --nodes=64 --time=00:01:00 --wrap="echo disabled_test" 2>&1)
    code=$?
    if [[ $code -eq 0 ]] && [[ "$output" =~ [0-9]+ ]]; then
        job_id=$(echo "$output" | grep -oP '[0-9]+' | tail -1)
        echo "  PASS: DISABLED mode bypasses all checks (job $job_id)"
        PASS=$((PASS + 1))
        scancel "$job_id" 2>/dev/null || true
        echo "  (cancelled test job $job_id)"
    else
        # Might fail due to resource limits, which is fine — the point is it wasn't blocked by isambard_sbatch
        if [[ "$output" == *"BLOCKED"* ]]; then
            echo "  FAIL: DISABLED mode should not block"
            FAIL=$((FAIL + 1))
        else
            echo "  PASS: DISABLED mode did not block (sbatch itself may have rejected: $output)"
            PASS=$((PASS + 1))
        fi
    fi
else
    skip_test "DISABLED mode" "squeue not found"
fi

# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
