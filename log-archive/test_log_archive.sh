#!/usr/bin/env bash
# ==============================================================================
# test_log_archive.sh - Automated Test Suite for log-archive
# ==============================================================================

set -uo pipefail

# Test workspace
TEST_ROOT="/tmp/log_archive_test_env_$$"
TEST_LOGS="$TEST_ROOT/logs"
TEST_ARCHIVES="$TEST_ROOT/archives"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CLI="$SCRIPT_DIR/log-archive.sh"

PASSED=0
FAILED=0
TOTAL=0

# Colors
GREEN=$'\033[1;32m'
RED=$'\033[1;31m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[1;36m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

setup() {
  cleanup
  mkdir -p "$TEST_LOGS" "$TEST_ARCHIVES"
  echo "2026-09-30 10:00:00 [INFO] System booted" > "$TEST_LOGS/system.log"
  echo "2026-09-30 10:01:00 [ERROR] Connection lost" > "$TEST_LOGS/error.log"
  echo "2026-09-30 10:02:00 [DEBUG] Temp cache" > "$TEST_LOGS/cache.tmp"
  mkdir -p "$TEST_LOGS/nginx"
  echo "127.0.0.1 GET / 200" > "$TEST_LOGS/nginx/access.log"
}

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local test_name="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$actual" -eq "$expected" ]; then
    printf "${GREEN}[PASS]${RESET} %s (exit code %d)\n" "$test_name" "$actual"
    PASSED=$((PASSED + 1))
  else
    printf "${RED}[FAIL]${RESET} %s (expected %d, got %d)\n" "$test_name" "$expected" "$actual"
    FAILED=$((FAILED + 1))
  fi
}

assert_file_exists() {
  local file="$1"
  local test_name="$2"
  TOTAL=$((TOTAL + 1))
  if [ -f "$file" ]; then
    printf "${GREEN}[PASS]${RESET} %s (file exists: %s)\n" "$test_name" "$(basename "$file")"
    PASSED=$((PASSED + 1))
  else
    printf "${RED}[FAIL]${RESET} %s (missing file: %s)\n" "$test_name" "$file"
    FAILED=$((FAILED + 1))
  fi
}

assert_output_contains() {
  local pattern="$1"
  local content="$2"
  local test_name="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$content" | grep -qE "$pattern"; then
    printf "${GREEN}[PASS]${RESET} %s\n" "$test_name"
    PASSED=$((PASSED + 1))
  else
    printf "${RED}[FAIL]${RESET} %s (pattern not found: '%s')\n" "$test_name" "$pattern"
    FAILED=$((FAILED + 1))
  fi
}

printf "\n${BOLD}%s${RESET}\n" "======================================================================"
printf "${BOLD}            RUNNING LOG-ARCHIVE AUTOMATED TEST SUITE                  ${RESET}\n"
printf "${BOLD}%s${RESET}\n\n" "======================================================================"

# Test 1: Help & Version
setup
output="$("$CLI" --help 2>&1)" || true
assert_output_contains "USAGE:" "$output" "Help flag displays usage menu"
assert_output_contains "log-archive(\.sh)? <log-directory>" "$output" "Help flag displays syntax"

output="$("$CLI" --version 2>&1)" || true
assert_output_contains "log-archive version 1.0.0" "$output" "Version flag displays correct version"

# Test 2: Missing Argument Error
setup
set +e
output="$("$CLI" 2>&1)"
code=$?
set -e
assert_exit_code 1 "$code" "Fails when no argument is provided"
assert_output_contains "Missing required argument" "$output" "Displays missing argument error"

# Test 3: Non-existent Directory Error
setup
set +e
output="$("$CLI" /non_existent_path_98765 2>&1)"
code=$?
set -e
assert_exit_code 1 "$code" "Fails on non-existent directory"
assert_output_contains "Directory does not exist" "$output" "Displays non-existent directory error"

# Test 4: Basic Archive Creation with Custom Output Directory (-o)
setup
output="$("$CLI" "$TEST_LOGS" -o "$TEST_ARCHIVES")"
code=$?
assert_exit_code 0 "$code" "Creates archive successfully"

# Find generated archive
archive_file="$(ls "$TEST_ARCHIVES"/logs_archive_*.tar.gz 2>/dev/null | head -n 1)"
assert_file_exists "$archive_file" "Archive tar.gz file was created"

checksum_file="${archive_file}.sha256"
assert_file_exists "$checksum_file" "Checksum .sha256 file was created"

history_log="$TEST_ARCHIVES/archive_history.log"
assert_file_exists "$history_log" "Archive history log file was created"

# Test 5: Verify Archive Integrity and Contents
TOTAL=$((TOTAL + 1))
if tar -tzf "$archive_file" | grep -q "logs/system.log"; then
  printf "${GREEN}[PASS]${RESET} Archive contains system.log inside relative path\n"
  PASSED=$((PASSED + 1))
else
  printf "${RED}[FAIL]${RESET} Archive missing system.log\n"
  FAILED=$((FAILED + 1))
fi

# Test 6: Verify Checksum Integrity
TOTAL=$((TOTAL + 1))
expected_hash="$(awk '{print $1}' "$checksum_file")"
actual_hash="$(shasum -a 256 "$archive_file" | awk '{print $1}')"
if [ "$expected_hash" = "$actual_hash" ]; then
  printf "${GREEN}[PASS]${RESET} SHA-256 checksum matches verified archive\n"
  PASSED=$((PASSED + 1))
else
  printf "${RED}[FAIL]${RESET} Checksum mismatch (expected %s, got %s)\n" "$expected_hash" "$actual_hash"
  FAILED=$((FAILED + 1))
fi

# Test 7: Verify History Log Entry Contents
log_content="$(cat "$history_log")"
assert_output_contains "SUCCESS \| Archive: logs_archive_" "$log_content" "History log contains SUCCESS record"
assert_output_contains "SHA256: [0-9a-f]{64}" "$log_content" "History log records SHA-256 hash"

# Test 8: Positional Output Directory: `log-archive <src> <dest>`
setup
dest_pos="$TEST_ROOT/pos_archives"
output="$("$CLI" "$TEST_LOGS" "$dest_pos")"
code=$?
assert_exit_code 0 "$code" "Positional destination argument works"
assert_file_exists "$(ls "$dest_pos"/logs_archive_*.tar.gz 2>/dev/null | head -n 1)" "Archive saved to positional destination"

# Test 9: File Exclusion (-e / --exclude)
setup
output="$("$CLI" "$TEST_LOGS" -o "$TEST_ARCHIVES" -e "*.tmp")"
code=$?
assert_exit_code 0 "$code" "Archive with --exclude runs successfully"
latest_archive="$(ls -t "$TEST_ARCHIVES"/logs_archive_*.tar.gz 2>/dev/null | head -n 1)"
TOTAL=$((TOTAL + 1))
if tar -tzf "$latest_archive" | grep -q "cache.tmp"; then
  printf "${RED}[FAIL]${RESET} Excluded file '*.tmp' was mistakenly included in archive\n"
  FAILED=$((FAILED + 1))
else
  printf "${GREEN}[PASS]${RESET} Excluded pattern '*.tmp' successfully omitted from archive\n"
  PASSED=$((PASSED + 1))
fi

# Test 10: Dry Run (-n / --dry-run)
setup
output="$("$CLI" "$TEST_LOGS" -o "$TEST_ARCHIVES" --dry-run)"
code=$?
assert_exit_code 0 "$code" "Dry-run exits with code 0"
assert_output_contains "DRY-RUN" "$output" "Dry-run banner indicated"
TOTAL=$((TOTAL + 1))
if ls "$TEST_ARCHIVES"/logs_archive_*.tar.gz >/dev/null 2>&1; then
  printf "${RED}[FAIL]${RESET} Dry-run created archive files on disk\n"
  FAILED=$((FAILED + 1))
else
  printf "${GREEN}[PASS]${RESET} Dry-run created no files on disk\n"
  PASSED=$((PASSED + 1))
fi

# Test 11: Quiet Mode (-q)
setup
output="$("$CLI" "$TEST_LOGS" -o "$TEST_ARCHIVES" -q)"
code=$?
assert_exit_code 0 "$code" "Quiet mode exits with code 0"
TOTAL=$((TOTAL + 1))
if [ -z "$output" ]; then
  printf "${GREEN}[PASS]${RESET} Quiet mode produces zero stdout\n"
  PASSED=$((PASSED + 1))
else
  printf "${RED}[FAIL]${RESET} Quiet mode produced output: '%s'\n" "$output"
  FAILED=$((FAILED + 1))
fi

# Test 12: Keep Quota Retention (-k 2)
setup
# Create 3 archives
"$CLI" "$TEST_LOGS" -o "$TEST_ARCHIVES" -q
sleep 1
"$CLI" "$TEST_LOGS" -o "$TEST_ARCHIVES" -q
sleep 1
"$CLI" "$TEST_LOGS" -o "$TEST_ARCHIVES" -k 2 -q

archive_count="$(ls "$TEST_ARCHIVES"/logs_archive_*.tar.gz 2>/dev/null | wc -l | tr -d ' ')"
TOTAL=$((TOTAL + 1))
if [ "$archive_count" -eq 2 ]; then
  printf "${GREEN}[PASS]${RESET} Keep quota (-k 2) retained exactly 2 archives (pruned excess)\n"
  PASSED=$((PASSED + 1))
else
  printf "${RED}[FAIL]${RESET} Keep quota failed (expected 2 archives, found %s)\n" "$archive_count"
  FAILED=$((FAILED + 1))
fi

# Test 13: History Viewer (-H)
output="$("$CLI" -l "$TEST_ARCHIVES/archive_history.log" -H 5)"
assert_output_contains "LOG ARCHIVE HISTORY" "$output" "History flag displays formatted log table"

# Test 14: Schedule Guide Output (--schedule)
output="$("$CLI" --schedule)"
assert_output_contains "CRONTAB AUTOMATION" "$output" "Schedule option prints crontab instructions"
assert_output_contains "SYSTEMD TIMER AUTOMATION" "$output" "Schedule option prints systemd instructions"

# Test 15: Source Directory Equals Destination Directory (No Silent Omission)
setup
output="$("$CLI" "$TEST_LOGS" -o "$TEST_LOGS" -q)"
code=$?
assert_exit_code 0 "$code" "Source == Destination runs successfully"
same_dir_archive="$(ls "$TEST_LOGS"/logs_archive_*.tar.gz 2>/dev/null | head -n 1)"
TOTAL=$((TOTAL + 1))
if tar -tzf "$same_dir_archive" | grep -q "logs/system.log"; then
  printf "${GREEN}[PASS]${RESET} Archive created inside source directory preserves source files\n"
  PASSED=$((PASSED + 1))
else
  printf "${RED}[FAIL]${RESET} Archive created inside source directory was empty (data loss bug)\n"
  FAILED=$((FAILED + 1))
fi

# Test 16: Sibling Directory Prefix Collision
setup
sib_src="$TEST_ROOT/app_logs"
sib_dest="$TEST_ROOT/app_logs_archive"
mkdir -p "$sib_src" "$sib_dest"
echo "data" > "$sib_src/app_logs_archive"
output="$("$CLI" "$sib_src" -o "$sib_dest" -q)"
code=$?
assert_exit_code 0 "$code" "Sibling destination runs successfully"
sib_archive="$(ls "$sib_dest"/logs_archive_*.tar.gz 2>/dev/null | head -n 1)"
TOTAL=$((TOTAL + 1))
if tar -tzf "$sib_archive" | grep -q "app_logs/app_logs_archive"; then
  printf "${GREEN}[PASS]${RESET} File named after sibling destination prefix is preserved in archive\n"
  PASSED=$((PASSED + 1))
else
  printf "${RED}[FAIL]${RESET} File named after sibling destination prefix was mistakenly excluded\n"
  FAILED=$((FAILED + 1))
fi

# Test 17: Paths with Spaces in Source and Destination
setup
spaces_src="$TEST_ROOT/my source logs"
spaces_dest="$TEST_ROOT/my output archives"
mkdir -p "$spaces_src" "$spaces_dest"
echo "data" > "$spaces_src/test space.log"
output="$("$CLI" "$spaces_src" -o "$spaces_dest" -q)"
code=$?
assert_exit_code 0 "$code" "Paths with spaces run successfully"
spaces_archive="$(ls "$spaces_dest"/logs_archive_*.tar.gz 2>/dev/null | head -n 1)"
TOTAL=$((TOTAL + 1))
if [ -n "$spaces_archive" ] && tar -tzf "$spaces_archive" | grep -q "test space.log"; then
  printf "${GREEN}[PASS]${RESET} Archive handles paths and filenames with spaces\n"
  PASSED=$((PASSED + 1))
else
  printf "${RED}[FAIL]${RESET} Failed to archive paths with spaces\n"
  FAILED=$((FAILED + 1))
fi

# Test 18: Unsearchable Source Directory (chmod 444, no +x) Graceful Error
setup
chmod 444 "$TEST_LOGS"
set +e
output="$("$CLI" "$TEST_LOGS" 2>&1)"
code=$?
set -e
chmod 755 "$TEST_LOGS"
assert_exit_code 1 "$code" "Unsearchable source directory exits with 1"
assert_output_contains "permission denied" "$output" "Displays permission denied error gracefully"

# Test 19: POSIX Double-Hyphen Delimiter (--)
setup
output="$("$CLI" -o "$TEST_ARCHIVES" -q -- "$TEST_LOGS")"
code=$?
assert_exit_code 0 "$code" "POSIX double-hyphen delimiter (--) accepted"

# Test 20: Rejection of Non-Positive Retention Values (-k 0 and -r 0)
setup
set +e
output_k0="$("$CLI" "$TEST_LOGS" -k 0 2>&1)"
code_k0=$?
output_r0="$("$CLI" "$TEST_LOGS" -r 0 2>&1)"
code_r0=$?
set -e
assert_exit_code 1 "$code_k0" "Fails on -k 0"
assert_output_contains "positive integer" "$output_k0" "Rejects 0 as keep count"
assert_exit_code 1 "$code_r0" "Fails on -r 0"
assert_output_contains "positive integer" "$output_r0" "Rejects 0 as retention days"

# ------------------------------------------------------------------------------
# Test Summary
# ------------------------------------------------------------------------------
printf "\n${BOLD}%s${RESET}\n" "======================================================================"
printf " Test Results: ${GREEN}%d passed${RESET}, ${RED}%d failed${RESET} (Total: %d)\n" "$PASSED" "$FAILED" "$TOTAL"
printf "${BOLD}%s${RESET}\n\n" "======================================================================"

if [ "$FAILED" -eq 0 ]; then
  exit 0
else
  exit 1
fi
