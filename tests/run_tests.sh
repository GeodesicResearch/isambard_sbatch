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
echo "── Unit Tests: bad_nodes_file_path ──"
# ─────────────────────────────────────────────────────────────────────────────

BAD_NODES_FILE="$TMPDIR_TESTS/bn.log"
result=$(bad_nodes_file_path)
assert_eq "file_path returns current env value" "$TMPDIR_TESTS/bn.log" "$result"

# Change env var mid-test to confirm helper reads it at call time
BAD_NODES_FILE="$TMPDIR_TESTS/other.log"
result=$(bad_nodes_file_path)
assert_eq "file_path re-reads BAD_NODES_FILE" "$TMPDIR_TESTS/other.log" "$result"

BAD_NODES_FILE="$TMPDIR_TESTS/bn.log"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Unit Tests: bad_nodes_read_active ──"
# ─────────────────────────────────────────────────────────────────────────────

BAD_NODES_FILE="$TMPDIR_TESTS/bn.log"
BAD_NODES_TTL=3600

# Missing file → empty output
rm -f "$BAD_NODES_FILE"
result=$(bad_nodes_read_active)
assert_eq "missing file" "" "$result"

# Empty file → empty output
: > "$BAD_NODES_FILE"
result=$(bad_nodes_read_active)
assert_eq "empty file" "" "$result"

# Fresh entry appears
now=$(date +%s)
printf '%s\tnid000001\ttunnel hung\talice\n' "$now" > "$BAD_NODES_FILE"
result=$(bad_nodes_read_active)
assert_eq "single fresh entry" "nid000001" "$result"

# All-expired entries → empty
old=$((now - 7200))  # 2 hours ago, TTL=1h
printf '%s\tnid000002\told\tbob\n' "$old" > "$BAD_NODES_FILE"
result=$(bad_nodes_read_active)
assert_eq "all-expired entries" "" "$result"

# Mixed fresh + expired → only fresh returned
{
    printf '%s\tnid000001\tfresh\talice\n' "$now"
    printf '%s\tnid000002\told\tbob\n' "$old"
} > "$BAD_NODES_FILE"
result=$(bad_nodes_read_active)
assert_eq "mixed fresh+expired" "nid000001" "$result"

# Duplicate node → deduped
{
    printf '%s\tnid000001\tfirst\talice\n' "$now"
    printf '%s\tnid000001\tsecond\tbob\n' "$now"
} > "$BAD_NODES_FILE"
result=$(bad_nodes_read_active)
assert_eq "duplicate node deduped" "nid000001" "$result"

# Malformed line (non-numeric epoch) → silently skipped
{
    printf 'notanepoch\tnid000bad\tbad\tmallory\n'
    printf '%s\tnid000001\tok\talice\n' "$now"
} > "$BAD_NODES_FILE"
result=$(bad_nodes_read_active)
assert_eq "malformed epoch skipped" "nid000001" "$result"

# Multiple distinct fresh nodes → all present
{
    printf '%s\tnid000001\t-\talice\n' "$now"
    printf '%s\tnid000002\t-\tbob\n' "$now"
    printf '%s\tnid000003\t-\tcarol\n' "$now"
} > "$BAD_NODES_FILE"
result=$(bad_nodes_read_active | sort | paste -sd, -)
assert_eq "three distinct fresh nodes" "nid000001,nid000002,nid000003" "$result"

# TTL boundary: entry exactly at TTL seconds old → expired (strict less-than)
boundary=$((now - 3600))
printf '%s\tnid_boundary\texact\talice\n' "$boundary" > "$BAD_NODES_FILE"
result=$(bad_nodes_read_active)
assert_eq "entry at exact TTL boundary is expired" "" "$result"

# TTL just-inside: entry ~50 min old with TTL=3600s → active
# (avoid race with seconds drift between $now and bad_nodes_read_active call)
just_inside=$((now - 3000))
printf '%s\tnid_just_inside\tstill-fresh\talice\n' "$just_inside" > "$BAD_NODES_FILE"
result=$(bad_nodes_read_active)
assert_eq "entry well within TTL is still active" "nid_just_inside" "$result"

# Future timestamp (clock skew) → still treated as active (does not crash)
future=$((now + 600))
printf '%s\tnid_future\tclock-skew\talice\n' "$future" > "$BAD_NODES_FILE"
result=$(bad_nodes_read_active)
assert_eq "future-timestamp entry is kept" "nid_future" "$result"

# Very old entry (30 days past) → expired
very_old=$((now - 2592000))
printf '%s\tnid_ancient\tvery-old\talice\n' "$very_old" > "$BAD_NODES_FILE"
result=$(bad_nodes_read_active)
assert_eq "30-day-old entry is expired" "" "$result"

# Empty line in file → silently skipped
{
    printf '\n'
    printf '%s\tnid_after_empty\tfresh\talice\n' "$now"
} > "$BAD_NODES_FILE"
result=$(bad_nodes_read_active)
assert_eq "empty line does not break parsing" "nid_after_empty" "$result"

# Entry with empty node field (epoch\t\treason) → skipped
{
    printf '%s\t\treason\talice\n' "$now"
    printf '%s\tnid_valid\tok\talice\n' "$now"
} > "$BAD_NODES_FILE"
result=$(bad_nodes_read_active)
assert_eq "empty node field skipped" "nid_valid" "$result"

# Epoch 0 → expired (now - 0 = now, which is >> TTL)
printf '0\tnid_epoch0\t-\talice\n' > "$BAD_NODES_FILE"
result=$(bad_nodes_read_active)
assert_eq "epoch 0 is expired" "" "$result"

# Idempotency: two consecutive reads return identical results
{
    printf '%s\tnid_a\t-\talice\n' "$now"
    printf '%s\tnid_b\t-\talice\n' "$now"
    printf '%s\tnid_c\t-\talice\n' "$now"
} > "$BAD_NODES_FILE"
first=$(bad_nodes_read_active)
second=$(bad_nodes_read_active)
assert_eq "read_active is idempotent" "$first" "$second"

# Many entries (50 distinct nodes) → all returned
rm -f "$BAD_NODES_FILE"
for i in $(seq -w 1 50); do
    printf '%s\tnid_bulk_%s\t-\talice\n' "$now" "$i" >> "$BAD_NODES_FILE"
done
result=$(bad_nodes_read_active | wc -l | tr -d ' ')
assert_eq "50 bulk entries all returned" "50" "$result"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Unit Tests: bad_nodes_mark ──"
# ─────────────────────────────────────────────────────────────────────────────

# Append one entry, verify 4 tab-separated fields
rm -f "$BAD_NODES_FILE"
bad_nodes_mark nid000099 "test reason" >/dev/null 2>&1
line=$(tail -1 "$BAD_NODES_FILE")
field_count=$(echo "$line" | awk -F'\t' '{print NF}')
assert_eq "mark appends 4 tab-separated fields" "4" "$field_count"

node_in_line=$(echo "$line" | awk -F'\t' '{print $2}')
assert_eq "mark writes correct node name" "nid000099" "$node_in_line"

reason_in_line=$(echo "$line" | awk -F'\t' '{print $3}')
assert_eq "mark writes correct reason" "test reason" "$reason_in_line"

# Reject invalid node name (shell metacharacter)
set +e
bad_nodes_mark "nid;rm" "bad" >/dev/null 2>&1
rc=$?
set -e
assert_exit_code "mark rejects shell metacharacter in node" "2" "$rc"

# Reject invalid node name (space)
set +e
bad_nodes_mark "nid 001" "bad" >/dev/null 2>&1
rc=$?
set -e
assert_exit_code "mark rejects space in node name" "2" "$rc"

# Missing node name → usage error
set +e
bad_nodes_mark "" "reason" >/dev/null 2>&1
rc=$?
set -e
assert_exit_code "mark rejects empty node name" "2" "$rc"

# Strip tabs from reason
rm -f "$BAD_NODES_FILE"
bad_nodes_mark nid000010 $'tab\there' >/dev/null 2>&1
reason_stored=$(tail -1 "$BAD_NODES_FILE" | awk -F'\t' '{print $3}')
assert_eq "mark strips tabs from reason" "tab here" "$reason_stored"

# Creates file if missing (when directory exists)
rm -f "$BAD_NODES_FILE"
bad_nodes_mark nid000011 "auto-create" >/dev/null 2>&1
assert_eq "mark creates missing file" "1" "$(test -f "$BAD_NODES_FILE" && echo 1 || echo 0)"

# Mark without reason (reason is optional)
rm -f "$BAD_NODES_FILE"
bad_nodes_mark nid000012 >/dev/null 2>&1
line=$(tail -1 "$BAD_NODES_FILE")
reason_field=$(echo "$line" | awk -F'\t' '{print $3}')
assert_eq "mark with no reason → empty reason field" "" "$reason_field"
user_field=$(echo "$line" | awk -F'\t' '{print $4}')
assert_eq "mark without reason still records user" "${USER:-unknown}" "$user_field"

# Mark with newline in reason → stripped
rm -f "$BAD_NODES_FILE"
bad_nodes_mark nid000013 $'line1\nline2' >/dev/null 2>&1
line_count=$(wc -l < "$BAD_NODES_FILE" | tr -d ' ')
assert_eq "mark with newline in reason stays one line" "1" "$line_count"
reason_stored=$(head -1 "$BAD_NODES_FILE" | awk -F'\t' '{print $3}')
assert_eq "newline in reason becomes space" "line1 line2" "$reason_stored"

# Mark rejects trailing whitespace (not in [A-Za-z0-9._-])
set +e
bad_nodes_mark "nid001 " "trailing space" >/dev/null 2>&1
rc=$?
set -e
assert_exit_code "mark rejects trailing space" "2" "$rc"

# Mark rejects empty node field in other ways (tab in name)
set +e
bad_nodes_mark $'nid\t001' "embedded tab" >/dev/null 2>&1
rc=$?
set -e
assert_exit_code "mark rejects embedded tab in node" "2" "$rc"

# Mark same node twice → both entries recorded (log is append-only)
rm -f "$BAD_NODES_FILE"
bad_nodes_mark nid000020 "first" >/dev/null 2>&1
bad_nodes_mark nid000020 "second" >/dev/null 2>&1
line_count=$(wc -l < "$BAD_NODES_FILE" | tr -d ' ')
assert_eq "same node marked twice → two lines" "2" "$line_count"
# But read_active dedupes the node
result=$(bad_nodes_read_active)
assert_eq "two entries for same node dedupe in read_active" "nid000020" "$result"

# Roundtrip: mark → read_active returns the node
rm -f "$BAD_NODES_FILE"
bad_nodes_mark nid000021 "roundtrip" >/dev/null 2>&1
result=$(bad_nodes_read_active)
assert_eq "mark → read_active roundtrip" "nid000021" "$result"

# Allowed characters: dot, underscore, hyphen
rm -f "$BAD_NODES_FILE"
for nodename in "nid.test" "nid_test" "nid-test" "nid.1_2-3"; do
    bad_nodes_mark "$nodename" "special char test" >/dev/null 2>&1
    rc=$?
    assert_exit_code "mark accepts '$nodename'" "0" "$rc"
done

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Unit Tests: bad_nodes_inject_exclude ──"
# ─────────────────────────────────────────────────────────────────────────────

# Helper to run inject_exclude and format output as comma-separated args
inject_out() {
    local -a out=()
    mapfile -d '' -t out < <(bad_nodes_inject_exclude "$@")
    local IFS='|'
    echo "${out[*]}"
}

# Empty bad-nodes file + no --exclude → argv unchanged
rm -f "$BAD_NODES_FILE"
: > "$BAD_NODES_FILE"
result=$(inject_out --nodes=1 --wrap="hostname")
assert_eq "empty log + no --exclude: argv unchanged" "--nodes=1|--wrap=hostname" "$result"

# Empty bad-nodes file + user --exclude → argv unchanged
result=$(inject_out --exclude=foo --nodes=1)
assert_eq "empty log + user --exclude: argv unchanged" "--exclude=foo|--nodes=1" "$result"

# Fresh entry + no user --exclude → --exclude appended
now=$(date +%s)
printf '%s\tnid000001\tfresh\talice\n' "$now" > "$BAD_NODES_FILE"
result=$(inject_out --nodes=1 --wrap="hostname")
assert_eq "one bad node + no --exclude" "--nodes=1|--wrap=hostname|--exclude=nid000001" "$result"

# Fresh entry + user --exclude=X → merged
result=$(inject_out --exclude=nid999 --nodes=1)
assert_eq "bad + user --exclude=X" "--nodes=1|--exclude=nid000001,nid999" "$result"

# Fresh entry + user --exclude X (space form) → merged
result=$(inject_out --exclude nid999 --nodes=1)
assert_eq "bad + user --exclude X (space)" "--nodes=1|--exclude=nid000001,nid999" "$result"

# Fresh entry + user -x X → merged
result=$(inject_out -x nid999 --nodes=1)
assert_eq "bad + user -x X" "--nodes=1|--exclude=nid000001,nid999" "$result"

# Two separate user --exclude args → both preserved in merged list
result=$(inject_out --exclude=nid998 --exclude=nid999 --nodes=1)
assert_eq "two user --exclude args merged" "--nodes=1|--exclude=nid000001,nid998,nid999" "$result"

# Multiple bad nodes → all in --exclude
{
    printf '%s\tnid000001\t-\talice\n' "$now"
    printf '%s\tnid000002\t-\tbob\n' "$now"
} > "$BAD_NODES_FILE"
result=$(inject_out --nodes=1 | tr '|' '\n' | grep -c '^nid00000[12]$\|^--exclude=.*nid000001.*nid000002')
[[ "$result" -ge 1 ]] && echo "  PASS: multiple bad nodes merged" && PASS=$((PASS + 1)) \
    || { echo "  FAIL: multiple bad nodes merged ($result)"; FAIL=$((FAIL + 1)); }

# All-expired entries → no --exclude injected
old=$((now - 7200))
printf '%s\tnid000002\told\tbob\n' "$old" > "$BAD_NODES_FILE"
result=$(inject_out --nodes=1 --wrap="hostname")
assert_eq "all-expired: no --exclude injected" "--nodes=1|--wrap=hostname" "$result"

# Bracket expression in user --exclude preserved (not split on comma)
printf '%s\tnid000001\t-\talice\n' "$now" > "$BAD_NODES_FILE"
result=$(inject_out --exclude="nid[100,200]" --nodes=1)
assert_eq "bracket expression preserved" "--nodes=1|--exclude=nid000001,nid[100,200]" "$result"

# -x=VALUE form (short option with =)
result=$(inject_out -x=nid999 --nodes=1)
assert_eq "-x=VALUE form parsed" "--nodes=1|--exclude=nid000001,nid999" "$result"

# -xVALUE attached form (short option with no separator)
result=$(inject_out -xnid999 --nodes=1)
assert_eq "-xNODE attached form parsed" "--nodes=1|--exclude=nid000001,nid999" "$result"

# Order preservation: other args keep their position; --exclude goes to end
result=$(inject_out --nodes=1 --wrap=cmd --time=01:00:00)
assert_eq "non-exclude args keep order, --exclude appended" \
    "--nodes=1|--wrap=cmd|--time=01:00:00|--exclude=nid000001" "$result"

# Positional script file is preserved
result=$(inject_out --nodes=1 myscript.sbatch arg1 arg2)
assert_eq "positional script + trailing args preserved" \
    "--nodes=1|myscript.sbatch|arg1|arg2|--exclude=nid000001" "$result"

# User --exclude anywhere in argv gets removed and re-added at end
result=$(inject_out --nodes=1 --exclude=nid999 --wrap=cmd)
assert_eq "--exclude removed from middle, re-appended at end" \
    "--nodes=1|--wrap=cmd|--exclude=nid000001,nid999" "$result"

# Many bad nodes → all joined in one --exclude
rm -f "$BAD_NODES_FILE"
for i in $(seq -w 1 10); do
    printf '%s\tnid_many_%s\t-\talice\n' "$now" "$i" >> "$BAD_NODES_FILE"
done
result=$(inject_out --nodes=1)
# Count commas in --exclude value to verify all 10 present
excl=$(echo "$result" | tr '|' '\n' | grep '^--exclude=' | head -1)
comma_count=$(echo "$excl" | tr -cd ',' | wc -c | tr -d ' ')
assert_eq "10 bad nodes produce 9 commas in --exclude" "9" "$comma_count"

# Large number (50) of bad nodes → all joined
rm -f "$BAD_NODES_FILE"
for i in $(seq -w 1 50); do
    printf '%s\tnid_big_%s\t-\talice\n' "$now" "$i" >> "$BAD_NODES_FILE"
done
result=$(inject_out --nodes=1)
excl=$(echo "$result" | tr '|' '\n' | grep '^--exclude=' | head -1)
comma_count=$(echo "$excl" | tr -cd ',' | wc -c | tr -d ' ')
assert_eq "50 bad nodes produce 49 commas in --exclude" "49" "$comma_count"

# Empty bad-nodes file + no user --exclude + mixed args → argv completely unchanged
rm -f "$BAD_NODES_FILE"
: > "$BAD_NODES_FILE"
result=$(inject_out --nodes=4 -J myjob myscript.sbatch arg1)
assert_eq "no bad nodes: argv passes through verbatim" \
    "--nodes=4|-J|myjob|myscript.sbatch|arg1" "$result"

# All-expired file + user --exclude → argv unchanged (user's --exclude stays put)
old_epoch=$((now - 7200))
printf '%s\tnid_expired\told\talice\n' "$old_epoch" > "$BAD_NODES_FILE"
result=$(inject_out --exclude=nid777 --nodes=1)
assert_eq "all-expired + user --exclude: argv unchanged" \
    "--exclude=nid777|--nodes=1" "$result"

# Reset for subsequent tests
rm -f "$BAD_NODES_FILE"
unset BAD_NODES_FILE BAD_NODES_TTL

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

    # ─────────────────────────────────────────────────────────────────────────
    # Bad-nodes integration tests
    # ─────────────────────────────────────────────────────────────────────────
    echo ""
    echo "── Integration Tests: Bad-nodes exclusion ──"

    BN_LOG="$TMPDIR_TESTS/bn_integration.log"
    BN_ENV=(ISAMBARD_SBATCH_BAD_NODES_FILE="$BN_LOG" ISAMBARD_SBATCH_BAD_NODES_TTL=3600)
    COMMON_ENV=(ISAMBARD_SBATCH_MAX_NODES=9999 ISAMBARD_SBATCH_ACCOUNT=brics.a5k ISAMBARD_SBATCH_DRY_RUN=1)

    # Test: fresh entry → dry-run output contains --exclude
    now_epoch=$(date +%s)
    printf '%s\tnid000777\ttunnel-hung\t%s\n' "$now_epoch" "$USER" > "$BN_LOG"
    output=$(env "${COMMON_ENV[@]}" "${BN_ENV[@]}" "$ISAMBARD_SBATCH" --nodes=1 --wrap="hostname" 2>&1) || true
    assert_contains "dry-run injects --exclude for fresh entry" "--exclude=nid000777" "$output"

    # Test: all-expired → no --exclude injected
    old_epoch=$((now_epoch - 7200))
    printf '%s\tnid000777\told\t%s\n' "$old_epoch" "$USER" > "$BN_LOG"
    output=$(env "${COMMON_ENV[@]}" "${BN_ENV[@]}" "$ISAMBARD_SBATCH" --nodes=1 --wrap="hostname" 2>&1) || true
    if [[ "$output" == *"--exclude="* ]]; then
        echo "  FAIL: expired entries should not produce --exclude"
        echo "        output: $output"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: expired entries produce no --exclude"
        PASS=$((PASS + 1))
    fi

    # Test: user --exclude + fresh bad node → merged
    printf '%s\tnid000777\tfresh\t%s\n' "$now_epoch" "$USER" > "$BN_LOG"
    output=$(env "${COMMON_ENV[@]}" "${BN_ENV[@]}" "$ISAMBARD_SBATCH" --exclude=nid000111 --nodes=1 --wrap="hostname" 2>&1) || true
    assert_contains "user --exclude merged with bad-node (has 111)" "nid000111" "$output"
    assert_contains "user --exclude merged with bad-node (has 777)" "nid000777" "$output"

    # Test: FORCE + fresh entry → dry-run output contains [FORCED] and --exclude
    output=$(env "${COMMON_ENV[@]}" "${BN_ENV[@]}" ISAMBARD_SBATCH_FORCE=1 \
        "$ISAMBARD_SBATCH" --nodes=64 --wrap="hostname" 2>&1) || true
    assert_contains "FORCE still marks [FORCED]" "[FORCED]" "$output"
    assert_contains "FORCE still injects --exclude" "--exclude=nid000777" "$output"

    # Test: DISABLED mode — should NOT inject (transparent passthrough path).
    # We check by running DRY_RUN=1 but DISABLED=1 goes straight to exec before
    # dry-run check, so we'll capture via a nonexistent REAL_SBATCH to avoid
    # actual submission. Use a harmless check: verify wrapper didn't reach the
    # injection code by checking "[DRY RUN]" is absent (DISABLED exits to sbatch).
    # Since a real submission might succeed, we'll skip if too sensitive.
    output=$(env ISAMBARD_SBATCH_DISABLED=1 "${BN_ENV[@]}" ISAMBARD_SBATCH_DRY_RUN=1 \
        "$ISAMBARD_SBATCH" --nodes=1 --wrap="echo disabled_path_marker" 2>&1) || true
    # DISABLED bypasses DRY_RUN, so output comes from real sbatch (job ID) or
    # an sbatch error. Either way, our "[DRY RUN]" sentinel should be absent
    # and our bad node should NOT have been injected.
    if [[ "$output" == *"[DRY RUN]"* ]]; then
        echo "  FAIL: DISABLED path should not print [DRY RUN] (should be passthrough)"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: DISABLED path bypasses wrapper logic (no [DRY RUN] sentinel)"
        PASS=$((PASS + 1))
        # Clean up any real job that may have been submitted
        if [[ "$output" =~ Submitted\ batch\ job\ ([0-9]+) ]]; then
            scancel "${BASH_REMATCH[1]}" 2>/dev/null || true
        fi
    fi

    # Test: --check mode with fresh bad node → no --exclude in output
    output=$(env "${BN_ENV[@]}" ISAMBARD_SBATCH_MAX_NODES=9999 ISAMBARD_SBATCH_ACCOUNT=brics.a5k \
        "$ISAMBARD_SBATCH" --check 2>&1) || true
    if [[ "$output" == *"--exclude"* ]]; then
        echo "  FAIL: --check should not reference --exclude"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: --check is inert to bad-nodes (no --exclude)"
        PASS=$((PASS + 1))
    fi

    # Test: --mark-bad then --list-bad roundtrip
    rm -f "$BN_LOG"
    output=$(env "${BN_ENV[@]}" "$ISAMBARD_SBATCH" --mark-bad nid000555 "smoke test" 2>&1) || true
    assert_contains "--mark-bad confirms on stderr" "marked 'nid000555'" "$output"
    assert_eq "--mark-bad creates file" "1" "$(test -f "$BN_LOG" && echo 1 || echo 0)"

    output=$(env "${BN_ENV[@]}" "$ISAMBARD_SBATCH" --list-bad 2>&1) || true
    assert_contains "--list-bad shows newly marked node" "nid000555" "$output"
    assert_contains "--list-bad shows reason" "smoke test" "$output"

    # Test: --list-bad with missing file → exits 0, no traceback
    rm -f "$BN_LOG"
    set +e
    env "${BN_ENV[@]}" "$ISAMBARD_SBATCH" --list-bad >/dev/null 2>&1
    rc=$?
    set -e
    assert_exit_code "--list-bad with missing file exits 0" "0" "$rc"

    # Test: --mark-bad rejects invalid node name
    set +e
    env "${BN_ENV[@]}" "$ISAMBARD_SBATCH" --mark-bad "nid;rm" "bad" >/dev/null 2>&1
    rc=$?
    set -e
    assert_exit_code "--mark-bad rejects shell metacharacter" "2" "$rc"

    # Test: submitting when bad-nodes dir is unmounted (simulated via nonexistent path)
    output=$(env ISAMBARD_SBATCH_MAX_NODES=9999 ISAMBARD_SBATCH_ACCOUNT=brics.a5k ISAMBARD_SBATCH_DRY_RUN=1 \
        ISAMBARD_SBATCH_BAD_NODES_FILE=/nonexistent/path/bn.log \
        "$ISAMBARD_SBATCH" --nodes=1 --wrap="hostname" 2>&1) || true
    assert_contains "nonexistent bad-nodes file does not block submission" "[DRY RUN] Would submit" "$output"
    if [[ "$output" == *"--exclude"* ]]; then
        echo "  FAIL: nonexistent file should not inject --exclude"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: nonexistent file is silent no-op"
        PASS=$((PASS + 1))
    fi

    # Test: bin/sbatch thin wrapper also injects bad nodes (delegates to isambard_sbatch)
    if [[ -x "$SBATCH_WRAPPER" ]]; then
        printf '%s\tnid000888\tvia-sbatch-wrapper\t%s\n' "$now_epoch" "$USER" > "$BN_LOG"
        output=$(env "${COMMON_ENV[@]}" "${BN_ENV[@]}" \
            "$SBATCH_WRAPPER" --nodes=1 --wrap="hostname" 2>&1) || true
        assert_contains "bin/sbatch wrapper also injects --exclude" "--exclude=nid000888" "$output"
    else
        skip_test "bin/sbatch wrapper + bad nodes" "wrapper not found"
    fi

    # Test: --list-bad output contains all four fields (date, node, reason, user)
    rm -f "$BN_LOG"
    env "${BN_ENV[@]}" "$ISAMBARD_SBATCH" --mark-bad nid000444 "list-format-check" >/dev/null 2>&1
    output=$(env "${BN_ENV[@]}" "$ISAMBARD_SBATCH" --list-bad 2>&1) || true
    assert_contains "--list-bad shows date (YYYY-)" "$(date +%Y-)" "$output"
    assert_contains "--list-bad shows node" "nid000444" "$output"
    assert_contains "--list-bad shows reason" "list-format-check" "$output"
    assert_contains "--list-bad shows user" "$USER" "$output"

    # Test: two marks of same node via subcommand → --list-bad shows both lines
    env "${BN_ENV[@]}" "$ISAMBARD_SBATCH" --mark-bad nid000444 "second-mark" >/dev/null 2>&1
    output=$(env "${BN_ENV[@]}" "$ISAMBARD_SBATCH" --list-bad 2>&1) || true
    line_count=$(echo "$output" | grep -c 'nid000444')
    assert_eq "two marks → two list lines" "2" "$line_count"
    # But the submission-time --exclude should only have it once (dedupe)
    output=$(env "${COMMON_ENV[@]}" "${BN_ENV[@]}" "$ISAMBARD_SBATCH" --nodes=1 --wrap="hostname" 2>&1) || true
    # Count occurrences of nid000444 in the --exclude value only
    excl_line=$(echo "$output" | grep -o -- '--exclude=[^ ]*' | head -1)
    occurrences=$(echo "$excl_line" | grep -o 'nid000444' | wc -l | tr -d ' ')
    assert_eq "--exclude dedupes repeated mark entries" "1" "$occurrences"

    # Test: TTL=1 with fresh entry from a few seconds ago → still active (<1s old)
    # but TTL=0 → nothing is ever active (strict <)
    rm -f "$BN_LOG"
    env "${BN_ENV[@]}" "$ISAMBARD_SBATCH" --mark-bad nid000333 "ttl-test" >/dev/null 2>&1
    output=$(env ISAMBARD_SBATCH_MAX_NODES=9999 ISAMBARD_SBATCH_ACCOUNT=brics.a5k ISAMBARD_SBATCH_DRY_RUN=1 \
        ISAMBARD_SBATCH_BAD_NODES_FILE="$BN_LOG" ISAMBARD_SBATCH_BAD_NODES_TTL=0 \
        "$ISAMBARD_SBATCH" --nodes=1 --wrap="hostname" 2>&1) || true
    if [[ "$output" == *"nid000333"* ]]; then
        echo "  FAIL: TTL=0 should exclude all entries from active list"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: TTL=0 hides all entries"
        PASS=$((PASS + 1))
    fi

    # Test: --mark-bad without reason succeeds
    rm -f "$BN_LOG"
    set +e
    env "${BN_ENV[@]}" "$ISAMBARD_SBATCH" --mark-bad nid000222 >/dev/null 2>&1
    rc=$?
    set -e
    assert_exit_code "--mark-bad without reason exits 0" "0" "$rc"

    # Test: --mark-bad without any node → usage error (rc=2)
    set +e
    env "${BN_ENV[@]}" "$ISAMBARD_SBATCH" --mark-bad >/dev/null 2>&1
    rc=$?
    set -e
    assert_exit_code "--mark-bad with no args exits 2" "2" "$rc"

    # Test: script-based submission (not --wrap) also injects --exclude
    printf '%s\tnid000666\tscript-path\t%s\n' "$now_epoch" "$USER" > "$BN_LOG"
    output=$(env "${COMMON_ENV[@]}" "${BN_ENV[@]}" \
        "$ISAMBARD_SBATCH" "$TMPDIR_TESTS/nodes4.sbatch" 2>&1) || true
    assert_contains "script-based submission injects --exclude" "--exclude=nid000666" "$output"

    # Test: injection interacts correctly with FORCE when DRY_RUN=0 would exec
    # (confirms the FORCE dry-run path rebuilds argv identically to main path)
    output=$(env ISAMBARD_SBATCH_MAX_NODES=0 ISAMBARD_SBATCH_ACCOUNT=brics.a5k \
        ISAMBARD_SBATCH_DRY_RUN=1 ISAMBARD_SBATCH_FORCE=1 \
        "${BN_ENV[@]}" \
        "$ISAMBARD_SBATCH" --exclude=nid111 --nodes=1 --wrap="hostname" 2>&1) || true
    assert_contains "FORCE dry-run merges user --exclude (111)" "nid111" "$output"
    assert_contains "FORCE dry-run merges bad --exclude (666)" "nid000666" "$output"

    # Test: --list-bad with expired-only file → reports "no active entries"
    old_epoch=$((now_epoch - 7200))
    printf '%s\tnid_old\t-\t%s\n' "$old_epoch" "$USER" > "$BN_LOG"
    output=$(env "${BN_ENV[@]}" "$ISAMBARD_SBATCH" --list-bad 2>&1) || true
    assert_contains "--list-bad reports no active when all expired" "no active bad-node entries" "$output"

    # Clean up
    rm -f "$BN_LOG"

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
