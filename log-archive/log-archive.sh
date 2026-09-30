#!/usr/bin/env bash
# ==============================================================================
# log-archive.sh - Log Archiving & Rotation CLI Tool
# ------------------------------------------------------------------------------
# Compresses logs from a specified directory into a timestamped tar.gz archive,
# records archive history to a log file, verifies archive integrity, and supports
# retention policies, remote backup sync, cloud upload, and alerts.
#
# Inspired by the roadmap.sh DevOps Project: Log Archive Tool
# (https://roadmap.sh/projects/log-archive-tool)
#
# Author : David Bassem (https://github.com/Davidbassemm)
# License: MIT
# ==============================================================================

set -euo pipefail

VERSION="1.0.0"
SCRIPT_NAME="$(basename "$0")"

# Default configurations
DEFAULT_OUTPUT_DIR="./archived_logs"
OUTPUT_DIR=""
LOG_FILE=""
RETENTION_DAYS=""
KEEP_COUNT=""
REMOTE_DEST=""
S3_DEST=""
EMAIL_TO=""
WEBHOOK_URL=""
VERBOSE=0
QUIET=0
DRY_RUN=0
GENERATE_CHECKSUM=1
EXCLUDE_PATTERNS=()
SHOW_SCHEDULE=0
SHOW_HISTORY=0
HISTORY_LIMIT=10

# Color Configuration
setup_colors() {
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    RESET=$'\033[0m'
    BLUE=$'\033[1;34m'
    CYAN=$'\033[1;36m'
    GREEN=$'\033[1;32m'
    YELLOW=$'\033[1;33m'
    RED=$'\033[1;31m'
    MAGENTA=$'\033[1;35m'
  else
    BOLD=""
    DIM=""
    RESET=""
    BLUE=""
    CYAN=""
    GREEN=""
    YELLOW=""
    RED=""
    MAGENTA=""
  fi
}

setup_colors

# Process interruption cleanup trap
cleanup_on_interrupt() {
  if [ -n "${ARCHIVE_FILEPATH:-}" ] && [ -f "$ARCHIVE_FILEPATH" ]; then
    rm -f "$ARCHIVE_FILEPATH" "${CHECKSUM_FILEPATH:-}" 2>/dev/null || true
  fi
  exit 130
}
trap cleanup_on_interrupt INT TERM

# ------------------------------------------------------------------------------
# Logging & Output Helpers
# ------------------------------------------------------------------------------
info() {
  if [ "$QUIET" -eq 0 ]; then
    printf "${CYAN}[+]${RESET} %s\n" "$*"
  fi
}

success() {
  if [ "$QUIET" -eq 0 ]; then
    printf "${GREEN}[✓]${RESET} %s\n" "$*"
  fi
}

warn() {
  if [ "$QUIET" -eq 0 ]; then
    printf "${YELLOW}[!]${RESET} %s\n" "$*" >&2
  fi
}

error() {
  printf "${RED}[✗] ERROR:${RESET} %s\n" "$*" >&2
}

debug() {
  if [ "$VERBOSE" -eq 1 ] && [ "$QUIET" -eq 0 ]; then
    printf "${DIM}[DEBUG] %s${RESET}\n" "$*"
  fi
}

# ------------------------------------------------------------------------------
# Help & Usage Manual
# ------------------------------------------------------------------------------
show_help() {
  cat <<EOF
${BOLD}log-archive v${VERSION}${RESET} - CLI Log Archiving & Compression Tool

${BOLD}USAGE:${RESET}
  $SCRIPT_NAME <log-directory> [output-directory] [OPTIONS]

${BOLD}ARGUMENTS:${RESET}
  <log-directory>             Path to the directory containing logs to archive
  [output-directory]          Optional destination directory (default: ${DEFAULT_OUTPUT_DIR})

${BOLD}OPTIONS:${RESET}
  -o, --output-dir <dir>      Destination directory to store compressed archives
  -l, --log-file <file>       Path to archive history log file (default: <output-dir>/archive_history.log)
  -r, --retention <days>      Purge archives older than <days> days
  -k, --keep <N>              Keep only the latest <N> archives, purging older ones
  -e, --exclude <pattern>     Exclude files/folders matching glob pattern (can repeat)
  -s, --remote <dest>         Sync archive to remote host via rsync/scp (e.g. user@host:/path)
  -c, --s3 <s3-uri>           Upload archive to AWS S3 bucket (e.g. s3://my-bucket/logs/)
  -m, --email <address>       Send completion notification email
  -w, --webhook <url>         Send completion JSON webhook payload (Slack/Discord/Custom API)
  -n, --dry-run               Simulate archiving without modifying files
      --no-checksum           Skip generating SHA-256 verification checksum
  -H, --history [N]           Display the last N entries of the archive history log (default: 10)
      --schedule              Print cron and systemd timer configuration examples
  -v, --verbose               Enable verbose output during archiving
  -q, --quiet                 Run silently without terminal output (ideal for cron jobs)
      --no-color              Disable ANSI colored output
  -h, --help                  Display this help menu and exit
  -V, --version               Display version information and exit

${BOLD}EXAMPLES:${RESET}
  # Basic archiving of /var/log (stored in ./archived_logs)
  $SCRIPT_NAME /var/log

  # Archive to a specific storage location
  $SCRIPT_NAME /var/log /backup/log_archives
  $SCRIPT_NAME /var/log -o /backup/log_archives

  # Archive with 30-day retention and file exclusions
  $SCRIPT_NAME /var/log -o /backup/logs -r 30 -e "*.sock" -e "*.tmp"

  # Keep only the last 10 archives and sync to remote server
  $SCRIPT_NAME /var/log/nginx -k 10 -s backup-user@nas.lan:/storage/nginx-backups/

  # Run quietly via cron with webhook alerts
  $SCRIPT_NAME /var/log -q -w "https://hooks.slack.com/services/XXX/YYY/ZZZ"

  # View recent archive history
  $SCRIPT_NAME --history 5

EOF
}

# ------------------------------------------------------------------------------
# Scheduling Automation Guide
# ------------------------------------------------------------------------------
show_schedule_guide() {
  cat <<'EOF'
==============================================================================
               AUTOMATED LOG ARCHIVING SCHEDULE CONFIGURATION                 
==============================================================================

1. CRONTAB AUTOMATION (Standard Linux / Unix / macOS)
------------------------------------------------------------------------------
Edit your crontab using:
  crontab -e

Add one of the following recommended schedules:

# A. Daily archive at 02:00 AM (Recommended for system logs)
0 2 * * * /usr/local/bin/log-archive /var/log -o /var/log/archives -r 30 -q >> /var/log/archives/cron.log 2>&1

# B. Weekly archive every Sunday at 03:30 AM
30 3 * * 0 /usr/local/bin/log-archive /var/log -o /backup/weekly -k 12 -q >> /backup/weekly/cron.log 2>&1

# C. Hourly archive for fast-growing web server logs (Nginx / Apache)
0 * * * * /usr/local/bin/log-archive /var/log/nginx -o /backup/nginx -k 48 -q >> /backup/nginx/cron.log 2>&1


2. SYSTEMD TIMER AUTOMATION (Modern Linux distributions)
------------------------------------------------------------------------------
Create the service unit file: `/etc/systemd/system/log-archive.service`

  [Unit]
  Description=Automated Log Archive Service
  After=network.target

  [Service]
  Type=oneshot
  ExecStart=/usr/local/bin/log-archive /var/log -o /var/log/archives -r 30 -q
  User=root

Create the timer unit file: `/etc/systemd/system/log-archive.timer`

  [Unit]
  Description=Run Log Archive Daily at 2:00 AM

  [Timer]
  OnCalendar=*-*-* 02:00:00
  Persistent=true

  [Install]
  WantedBy=timers.target

Enable and activate the timer:
  sudo systemctl daemon-reload
  sudo systemctl enable --now log-archive.timer
  systemctl list-timers --all | grep log-archive

==============================================================================
EOF
}

# ------------------------------------------------------------------------------
# History Log Viewer
# ------------------------------------------------------------------------------
display_history() {
  local target_log="${LOG_FILE}"
  if [ -z "$target_log" ]; then
    if [ -n "$OUTPUT_DIR" ] && [ -f "$OUTPUT_DIR/archive_history.log" ]; then
      target_log="$OUTPUT_DIR/archive_history.log"
    elif [ -f "./archived_logs/archive_history.log" ]; then
      target_log="./archived_logs/archive_history.log"
    elif [ -f "/var/log/archives/archive_history.log" ]; then
      target_log="/var/log/archives/archive_history.log"
    fi
  fi

  if [ -z "$target_log" ] || [ ! -f "$target_log" ]; then
    warn "No archive history log file found."
    printf "Expected locations: %s\n" "${DEFAULT_OUTPUT_DIR}/archive_history.log"
    return 0
  fi

  printf "${BOLD}%s${RESET}\n" "======================================================================"
  printf "${BOLD}             LOG ARCHIVE HISTORY (Last %d entries)                    ${RESET}\n" "$HISTORY_LIMIT"
  printf "${BOLD}%s${RESET}\n" "======================================================================"
  printf "${DIM}Log file: %s${RESET}\n\n" "$target_log"

  tail -n "$HISTORY_LIMIT" "$target_log"
  echo ""
}

# ------------------------------------------------------------------------------
# Utility Functions
# ------------------------------------------------------------------------------

# Resolve canonical directory path portably
resolve_dir_path() {
  local target="$1"
  if [ -d "$target" ] && [ -x "$target" ]; then
    (cd -- "$target" 2>/dev/null && pwd -P)
  else
    local parent
    parent="$(dirname -- "$target")"
    local base
    base="$(basename -- "$target")"
    if [ -d "$parent" ] && [ -x "$parent" ]; then
      echo "$(cd -- "$parent" 2>/dev/null && pwd -P)/$base"
    else
      echo "$target"
    fi
  fi
}

# Portable file size in bytes
get_file_size() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "0"
    return
  fi
  if stat -c %s "$file" >/dev/null 2>&1; then
    stat -c %s "$file"
  elif stat -f %z "$file" >/dev/null 2>&1; then
    stat -f %z "$file"
  else
    wc -c < "$file" | tr -d ' '
  fi
}

# Human-readable size converter (B, KB, MB, GB)
format_size() {
  local bytes="${1:-0}"
  if [ -z "$bytes" ] || ! [ "$bytes" -ge 0 ] 2>/dev/null; then
    echo "0 B"
    return
  fi
  if [ "$bytes" -ge 1073741824 ]; then
    awk "BEGIN {printf \"%.2f GB\", $bytes / 1073741824}"
  elif [ "$bytes" -ge 1048576 ]; then
    awk "BEGIN {printf \"%.2f MB\", $bytes / 1048576}"
  elif [ "$bytes" -ge 1024 ]; then
    awk "BEGIN {printf \"%.2f KB\", $bytes / 1024}"
  else
    echo "${bytes} B"
  fi
}

# Calculate directory size in bytes
get_dir_size() {
  local dir="$1"
  if du -sk "$dir" >/dev/null 2>&1; then
    local kb
    kb="$(du -sk "$dir" 2>/dev/null | awk '{print $1}')"
    echo "$((kb * 1024))"
  else
    echo "0"
  fi
}

# Count files inside directory
count_files() {
  local dir="$1"
  find "$dir" -type f 2>/dev/null | wc -l | tr -d ' '
}

# Calculate SHA-256 Checksum
calc_sha256() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file" | awk '{print $NF}'
  else
    echo "N/A"
  fi
}

# ------------------------------------------------------------------------------
# Retention & Rotation Policies
# ------------------------------------------------------------------------------
apply_retention_policy() {
  local dir="$1"
  local history_log="$2"

  if [ -n "$RETENTION_DAYS" ] && [ "$RETENTION_DAYS" -gt 0 ] 2>/dev/null; then
    info "Applying retention policy: Purging archives older than $RETENTION_DAYS days..."
    
    # Locate matching archives
    local old_files=()
    while IFS= read -r f; do
      [ -n "$f" ] && old_files+=("$f")
    done < <(find "$dir" -maxdepth 1 -name "logs_archive_*.tar.gz" -type f -mtime "+$RETENTION_DAYS" 2>/dev/null || true)

    if [ ${#old_files[@]} -gt 0 ]; then
      for file in "${old_files[@]}"; do
        if [ "$DRY_RUN" -eq 1 ]; then
          info "[DRY-RUN] Would remove old archive: $(basename "$file")"
        else
          rm -f "$file" "${file}.sha256"
          success "Purged expired archive: $(basename "$file")"
          printf "[%s] PURGE | Removed expired archive: %s (>%d days)\n" \
            "$(date '+%Y-%m-%d %H:%M:%S')" "$(basename "$file")" "$RETENTION_DAYS" >> "$history_log"
        fi
      done
    else
      debug "No archives found older than $RETENTION_DAYS days."
    fi
  fi

  if [ -n "$KEEP_COUNT" ] && [ "$KEEP_COUNT" -gt 0 ] 2>/dev/null; then
    info "Applying keep count policy: Retaining latest $KEEP_COUNT archives..."

    local all_archives=()
    # Sort files by modification time, newest first
    while IFS= read -r f; do
      [ -n "$f" ] && all_archives+=("$f")
    done < <(ls -t "$dir"/logs_archive_*.tar.gz 2>/dev/null || true)

    local total="${#all_archives[@]}"
    if [ "$total" -gt "$KEEP_COUNT" ]; then
      local idx=0
      for file in "${all_archives[@]}"; do
        idx=$((idx + 1))
        if [ "$idx" -gt "$KEEP_COUNT" ]; then
          if [ "$DRY_RUN" -eq 1 ]; then
            info "[DRY-RUN] Would remove excess archive #$idx: $(basename "$file")"
          else
            rm -f "$file" "${file}.sha256"
            success "Removed excess archive: $(basename "$file")"
            printf "[%s] PURGE | Removed excess archive: %s (Keep quota: %d)\n" \
              "$(date '+%Y-%m-%d %H:%M:%S')" "$(basename "$file")" "$KEEP_COUNT" >> "$history_log"
          fi
        fi
      done
    else
      debug "Archive count ($total) is within keep quota ($KEEP_COUNT)."
    fi
  fi
}

# ------------------------------------------------------------------------------
# Notifications & Integrations
# ------------------------------------------------------------------------------
send_email_notification() {
  local recipient="$1"
  local archive_name="$2"
  local archive_size="$3"
  local duration="$4"
  local log_dir="$5"
  local sha256="$6"

  if [ -z "$recipient" ]; then
    return 0
  fi

  info "Sending email report to $recipient..."

  local subject="[Log Archive] Backup Completed: $archive_name"
  local body
  body=$(cat <<EOF
Log Archive Notification
========================================
Status       : SUCCESS
Archive Name : $archive_name
Source Dir   : $log_dir
Archive Size : $archive_size
Duration     : ${duration}s
SHA-256      : $sha256
Timestamp    : $(date '+%Y-%m-%d %H:%M:%S %Z')
Host         : $(hostname)
========================================
Automated by log-archive CLI tool.
EOF
)

  if command -v mail >/dev/null 2>&1; then
    printf "%s\n" "$body" | mail -s "$subject" "$recipient" 2>/dev/null && success "Email sent via mail utility." || warn "Failed to send email via 'mail'."
  elif command -v sendmail >/dev/null 2>&1; then
    printf "To: %s\nSubject: %s\n\n%s\n" "$recipient" "$subject" "$body" | sendmail -t 2>/dev/null && success "Email sent via sendmail." || warn "Failed to send email via 'sendmail'."
  else
    warn "Neither 'mail' nor 'sendmail' is installed. Email notification skipped."
  fi
}

send_webhook_notification() {
  local webhook_url="$1"
  local archive_name="$2"
  local archive_size="$3"
  local duration="$4"
  local log_dir="$5"
  local sha256="$6"

  if [ -z "$webhook_url" ]; then
    return 0
  fi

  info "Dispatching webhook notification..."

  if ! command -v curl >/dev/null 2>&1; then
    warn "'curl' is required for webhook notifications. Skipped."
    return 0
  fi

  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local hostname
  hostname="$(hostname)"

  # Sanitize fields for valid JSON output
  local safe_dir="${log_dir//\\/\\\\}"
  safe_dir="${safe_dir//\"/\\\"}"
  local safe_name="${archive_name//\\/\\\\}"
  safe_name="${safe_name//\"/\\\"}"
  local safe_host="${hostname//\\/\\\\}"
  safe_host="${safe_host//\"/\\\"}"

  # Generic webhook JSON payload compatible with Slack, Discord, or Custom APIs
  local payload
  payload=$(cat <<EOF
{
  "text": "Log Archive Completed: ${safe_name} (${archive_size}) on ${safe_host}",
  "event": "log_archive_completed",
  "status": "success",
  "archive_file": "${safe_name}",
  "source_directory": "${safe_dir}",
  "archive_size": "${archive_size}",
  "duration_seconds": ${duration},
  "sha256": "${sha256}",
  "timestamp": "${timestamp}",
  "hostname": "${safe_host}"
}
EOF
)

  local http_code
  http_code=$(curl -s --connect-timeout 5 --max-time 15 -o /dev/null -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$webhook_url" 2>/dev/null || echo "000")

  if [[ "$http_code" =~ ^(200|201|204)$ ]]; then
    success "Webhook delivered successfully (HTTP $http_code)."
  else
    warn "Webhook delivery returned status HTTP $http_code."
  fi
}

sync_remote_destination() {
  local archive_path="$1"
  local remote_dest="$2"

  if [ -z "$remote_dest" ]; then
    return 0
  fi

  info "Syncing archive to remote destination: $remote_dest"

  if command -v rsync >/dev/null 2>&1; then
    if rsync -avz "$archive_path" "$remote_dest"; then
      success "Remote sync completed via rsync."
    else
      error "rsync to $remote_dest failed."
      return 1
    fi
  elif command -v scp >/dev/null 2>&1; then
    if scp "$archive_path" "$remote_dest"; then
      success "Remote copy completed via scp."
    else
      error "scp to $remote_dest failed."
      return 1
    fi
  else
    error "Neither 'rsync' nor 'scp' found on system. Cannot sync remotely."
    return 1
  fi
}

upload_to_s3() {
  local archive_path="$1"
  local s3_dest="$2"

  if [ -z "$s3_dest" ]; then
    return 0
  fi

  info "Uploading archive to AWS S3: $s3_dest"

  if command -v aws >/dev/null 2>&1; then
    if aws s3 cp "$archive_path" "$s3_dest"; then
      success "S3 upload completed successfully."
    else
      error "AWS S3 upload failed."
      return 1
    fi
  else
    error "AWS CLI ('aws') is not installed. S3 upload skipped."
    return 1
  fi
}

# ------------------------------------------------------------------------------
# Argument Parsing
# ------------------------------------------------------------------------------
LOG_DIR=""
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -V|--version)
      echo "log-archive version $VERSION"
      exit 0
      ;;
    --schedule)
      show_schedule_guide
      exit 0
      ;;
    -H|--history)
      SHOW_HISTORY=1
      if [[ $# -gt 1 ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
        HISTORY_LIMIT="$2"
        shift
      fi
      shift
      ;;
    -o|--output-dir)
      if [[ $# -lt 2 ]] || [[ "$2" =~ ^- ]]; then
        error "Option '$1' requires a valid directory argument."
        exit 1
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -l|--log-file)
      if [[ $# -lt 2 ]] || [[ "$2" =~ ^- ]]; then
        error "Option '$1' requires a file path argument."
        exit 1
      fi
      LOG_FILE="$2"
      shift 2
      ;;
    -r|--retention)
      if [[ $# -lt 2 ]] || ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
        error "Option '$1' requires a positive integer representing days."
        exit 1
      fi
      RETENTION_DAYS="$2"
      shift 2
      ;;
    -k|--keep)
      if [[ $# -lt 2 ]] || ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
        error "Option '$1' requires a positive integer representing number of archives."
        exit 1
      fi
      KEEP_COUNT="$2"
      shift 2
      ;;
    -e|--exclude)
      if [[ $# -lt 2 ]] || [[ "$2" =~ ^- ]]; then
        error "Option '$1' requires a pattern argument."
        exit 1
      fi
      EXCLUDE_PATTERNS+=("$2")
      shift 2
      ;;
    -s|--remote)
      if [[ $# -lt 2 ]] || [[ "$2" =~ ^- ]]; then
        error "Option '$1' requires a destination argument (e.g. user@host:/path)."
        exit 1
      fi
      REMOTE_DEST="$2"
      shift 2
      ;;
    -c|--s3)
      if [[ $# -lt 2 ]] || [[ "$2" =~ ^- ]]; then
        error "Option '$1' requires an S3 bucket URI (e.g. s3://bucket/path)."
        exit 1
      fi
      S3_DEST="$2"
      shift 2
      ;;
    -m|--email)
      if [[ $# -lt 2 ]] || [[ "$2" =~ ^- ]]; then
        error "Option '$1' requires an email address."
        exit 1
      fi
      EMAIL_TO="$2"
      shift 2
      ;;
    -w|--webhook)
      if [[ $# -lt 2 ]] || [[ "$2" =~ ^- ]]; then
        error "Option '$1' requires a webhook URL."
        exit 1
      fi
      WEBHOOK_URL="$2"
      shift 2
      ;;
    -n|--dry-run)
      DRY_RUN=1
      shift
      ;;
    --no-checksum)
      GENERATE_CHECKSUM=0
      shift
      ;;
    -v|--verbose)
      VERBOSE=1
      shift
      ;;
    -q|--quiet)
      QUIET=1
      shift
      ;;
    --no-color)
      NO_COLOR=1
      setup_colors
      shift
      ;;
    --)
      shift
      POSITIONAL_ARGS+=("$@")
      break
      ;;
    -*)
      error "Unknown option: $1"
      echo "Use '$SCRIPT_NAME --help' to see available options." >&2
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

# If --history requested alone
if [ "$SHOW_HISTORY" -eq 1 ] && [ ${#POSITIONAL_ARGS[@]} -eq 0 ]; then
  display_history
  exit 0
fi

# Map positional arguments
if [ ${#POSITIONAL_ARGS[@]} -ge 1 ]; then
  LOG_DIR="${POSITIONAL_ARGS[0]}"
fi

if [ ${#POSITIONAL_ARGS[@]} -ge 2 ] && [ -z "$OUTPUT_DIR" ]; then
  OUTPUT_DIR="${POSITIONAL_ARGS[1]}"
fi

# Validation: Required Argument
if [ -z "$LOG_DIR" ]; then
  error "Missing required argument: <log-directory>"
  echo "" >&2
  show_help >&2
  exit 1
fi

# Check if log directory exists and is accessible
if [ ! -d "$LOG_DIR" ]; then
  error "Directory does not exist or is not a directory: '$LOG_DIR'"
  exit 1
fi

if [ ! -r "$LOG_DIR" ]; then
  error "Cannot read directory (permission denied): '$LOG_DIR'"
  exit 1
fi

if [ ! -x "$LOG_DIR" ]; then
  error "Cannot enter directory (search/execute permission denied): '$LOG_DIR'"
  exit 1
fi

# Resolve paths
RESOLVED_LOG_DIR="$(resolve_dir_path "$LOG_DIR")"

# Default Output Directory resolution
if [ -z "$OUTPUT_DIR" ]; then
  OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
fi

RESOLVED_OUTPUT_DIR="$(resolve_dir_path "$OUTPUT_DIR")"

# Default History Log File
if [ -z "$LOG_FILE" ]; then
  LOG_FILE="${RESOLVED_OUTPUT_DIR}/archive_history.log"
fi

# ------------------------------------------------------------------------------
# Archive Execution Preparation
# ------------------------------------------------------------------------------
TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"
ARCHIVE_FILENAME="logs_archive_${TIMESTAMP}.tar.gz"
ARCHIVE_FILEPATH="${RESOLVED_OUTPUT_DIR}/${ARCHIVE_FILENAME}"
CHECKSUM_FILEPATH="${ARCHIVE_FILEPATH}.sha256"

START_TIME=$(date +%s)
TOTAL_FILES=$(count_files "$RESOLVED_LOG_DIR")
RAW_BYTES=$(get_dir_size "$RESOLVED_LOG_DIR")
FORMATTED_RAW_SIZE="$(format_size "$RAW_BYTES")"

if [ "$QUIET" -eq 0 ]; then
  printf "${BOLD}%s${RESET}\n" "======================================================================"
  printf "${BOLD}                 LOG ARCHIVE & COMPRESSION TOOL                       ${RESET}\n"
  printf "${BOLD}%s${RESET}\n" "======================================================================"
  printf " Timestamp          : %s\n" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
  printf " Source Directory   : %s\n" "$RESOLVED_LOG_DIR"
  printf " Files to Archive   : %s files (%s)\n" "$TOTAL_FILES" "$FORMATTED_RAW_SIZE"
  printf " Destination Dir    : %s\n" "$RESOLVED_OUTPUT_DIR"
  printf " Target Archive     : %s\n" "$ARCHIVE_FILENAME"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf " Execution Mode     : ${YELLOW}DRY-RUN (Simulation Only)${RESET}\n"
  fi
  printf "%s\n\n" "----------------------------------------------------------------------"
fi

if [ "$TOTAL_FILES" -eq 0 ]; then
  warn "Directory '$RESOLVED_LOG_DIR' does not contain any regular files."
fi

# Ensure output directory exists and is writable
if [ "$DRY_RUN" -eq 0 ]; then
  if ! mkdir -p "$RESOLVED_OUTPUT_DIR" 2>/dev/null || [ ! -w "$RESOLVED_OUTPUT_DIR" ]; then
    error "Cannot write to archive destination directory: '$RESOLVED_OUTPUT_DIR'. Check permissions."
    exit 1
  fi
fi

# Prepare Tar Exclude Flags
TAR_ARGS=()

# Protect against recursion if output directory is inside the source log directory
if [ "$RESOLVED_OUTPUT_DIR" = "$RESOLVED_LOG_DIR" ]; then
  debug "Output directory is the source directory. Excluding archive artifacts."
  TAR_ARGS+=("--exclude=logs_archive_*.tar.gz")
  TAR_ARGS+=("--exclude=logs_archive_*.tar.gz.sha256")
  TAR_ARGS+=("--exclude=archive_history.log")
elif [[ "$RESOLVED_OUTPUT_DIR" == "$RESOLVED_LOG_DIR"/* ]]; then
  debug "Output directory is inside source directory. Excluding destination."
  REL_OUTPUT="${RESOLVED_OUTPUT_DIR#"$RESOLVED_LOG_DIR"/}"
  TAR_ARGS+=("--exclude=${REL_OUTPUT}")
fi

# User specified exclude patterns
if [ ${#EXCLUDE_PATTERNS[@]} -gt 0 ]; then
  for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    TAR_ARGS+=("--exclude=${pattern}")
  done
fi

# Parent directory and base name for clean relative archiving
PARENT_DIR="$(dirname "$RESOLVED_LOG_DIR")"
TARGET_DIR_NAME="$(basename "$RESOLVED_LOG_DIR")"

info "Compressing logs into $ARCHIVE_FILENAME..."

if [ "$DRY_RUN" -eq 1 ]; then
  info "[DRY-RUN] Would execute: tar -czf \"$ARCHIVE_FILEPATH\" -C \"$PARENT_DIR\" \"$TARGET_DIR_NAME\""
  info "[DRY-RUN] Simulating successful completion."
  success "Dry run completed successfully. No files created."
  exit 0
fi

# ------------------------------------------------------------------------------
# Compress Logs via tar
# ------------------------------------------------------------------------------
TAR_EXEC_ARGS=("-czf" "$ARCHIVE_FILEPATH")
if [ "$VERBOSE" -eq 1 ]; then
  TAR_EXEC_ARGS=("-cvzf" "$ARCHIVE_FILEPATH")
fi

if [ ${#TAR_ARGS[@]} -gt 0 ]; then
  TAR_EXEC_ARGS=("${TAR_ARGS[@]}" "${TAR_EXEC_ARGS[@]}")
fi

TAR_EXEC_ARGS+=("-C" "$PARENT_DIR" "$TARGET_DIR_NAME")

debug "Running: tar ${TAR_EXEC_ARGS[*]}"

# Execute tar compression
if ! tar "${TAR_EXEC_ARGS[@]}" 2>/dev/null; then
  # Some systems / sockets may return warning codes; check if file was created
  if [ ! -f "$ARCHIVE_FILEPATH" ] || [ ! -s "$ARCHIVE_FILEPATH" ]; then
    error "Compression failed: tar could not create archive '$ARCHIVE_FILEPATH'."
    
    # Record failure in history log
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    printf "[%s] FAILED | Directory: %s | Error: tar compression failure\n" \
      "$(date '+%Y-%m-%d %H:%M:%S')" "$RESOLVED_LOG_DIR" >> "$LOG_FILE" 2>/dev/null || true
    exit 2
  fi
fi

# ------------------------------------------------------------------------------
# Verify Archive Integrity
# ------------------------------------------------------------------------------
info "Verifying archive integrity..."
if ! tar -tzf "$ARCHIVE_FILEPATH" >/dev/null 2>&1; then
  error "Archive verification failed! The generated tar.gz is corrupted."
  rm -f "$ARCHIVE_FILEPATH"
  printf "[%s] FAILED | File: %s | Error: Corrupted archive failed integrity test\n" \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$ARCHIVE_FILENAME" >> "$LOG_FILE" 2>/dev/null || true
  exit 2
fi
success "Archive integrity verified."

# ------------------------------------------------------------------------------
# Metrics & Checksums
# ------------------------------------------------------------------------------
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
[ "$DURATION" -le 0 ] && DURATION=1

COMPRESSED_BYTES="$(get_file_size "$ARCHIVE_FILEPATH")"
FORMATTED_COMPRESSED_SIZE="$(format_size "$COMPRESSED_BYTES")"

# Calculate compression ratio
if [ "$RAW_BYTES" -gt 0 ] && [ "$COMPRESSED_BYTES" -gt 0 ]; then
  SAVED_PCT=$(awk -v raw="$RAW_BYTES" -v comp="$COMPRESSED_BYTES" 'BEGIN {
    saved = (1 - (comp / raw)) * 100;
    if (saved < 0) saved = 0.0;
    printf "%.1f", saved;
  }')
else
  SAVED_PCT="0.0"
fi

SHA256_HASH="N/A"
if [ "$GENERATE_CHECKSUM" -eq 1 ]; then
  SHA256_HASH="$(calc_sha256 "$ARCHIVE_FILEPATH")"
  echo "$SHA256_HASH  $ARCHIVE_FILENAME" > "$CHECKSUM_FILEPATH"
  debug "SHA256: $SHA256_HASH"
fi

# ------------------------------------------------------------------------------
# Record Archive Date & Time to Log File (Required by Spec)
# ------------------------------------------------------------------------------
RECORD_TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
HISTORY_RECORD=$(printf "[%s] SUCCESS | Archive: %s | Source: %s | Original: %s (%s files) | Compressed: %s (%s%% saved) | Duration: %ss | SHA256: %s" \
  "$RECORD_TIMESTAMP" "$ARCHIVE_FILENAME" "$RESOLVED_LOG_DIR" "$FORMATTED_RAW_SIZE" "$TOTAL_FILES" "$FORMATTED_COMPRESSED_SIZE" "$SAVED_PCT" "$DURATION" "$SHA256_HASH")

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
echo "$HISTORY_RECORD" >> "$LOG_FILE"
success "Archive event recorded in history log: $LOG_FILE"

# ------------------------------------------------------------------------------
# Apply Retention Policies (Stretch Goal)
# ------------------------------------------------------------------------------
apply_retention_policy "$RESOLVED_OUTPUT_DIR" "$LOG_FILE"

# ------------------------------------------------------------------------------
# Sync / Upload / Notify (Stretch Goals)
# ------------------------------------------------------------------------------
REMOTE_ERRORS=0
if [ -n "$REMOTE_DEST" ]; then
  if ! sync_remote_destination "$ARCHIVE_FILEPATH" "$REMOTE_DEST"; then
    REMOTE_ERRORS=$((REMOTE_ERRORS + 1))
  fi
fi

if [ -n "$S3_DEST" ]; then
  if ! upload_to_s3 "$ARCHIVE_FILEPATH" "$S3_DEST"; then
    REMOTE_ERRORS=$((REMOTE_ERRORS + 1))
  fi
fi

if [ -n "$EMAIL_TO" ]; then
  send_email_notification "$EMAIL_TO" "$ARCHIVE_FILENAME" "$FORMATTED_COMPRESSED_SIZE" "$DURATION" "$RESOLVED_LOG_DIR" "$SHA256_HASH"
fi

if [ -n "$WEBHOOK_URL" ]; then
  send_webhook_notification "$WEBHOOK_URL" "$ARCHIVE_FILENAME" "$FORMATTED_COMPRESSED_SIZE" "$DURATION" "$RESOLVED_LOG_DIR" "$SHA256_HASH"
fi

# ------------------------------------------------------------------------------
# Summary Output
# ------------------------------------------------------------------------------
if [ "$QUIET" -eq 0 ]; then
  echo ""
  printf "${BOLD}%s${RESET}\n" "======================================================================"
  if [ "$REMOTE_ERRORS" -gt 0 ]; then
    printf "${YELLOW}${BOLD}     ARCHIVE COMPLETED LOCALLY (REMOTE SYNC/UPLOAD FAILED)           ${RESET}\n"
  else
    printf "${GREEN}${BOLD}                 ARCHIVE COMPLETED SUCCESSFULLY                       ${RESET}\n"
  fi
  printf "${BOLD}%s${RESET}\n" "======================================================================"
  printf " Archive File       : %s\n" "${GREEN}${ARCHIVE_FILEPATH}${RESET}"
  printf " Original Size      : %s (%s files)\n" "$FORMATTED_RAW_SIZE" "$TOTAL_FILES"
  printf " Compressed Size    : %s\n" "${BOLD}${FORMATTED_COMPRESSED_SIZE}${RESET}"
  printf " Space Saved        : %s%%\n" "${GREEN}${SAVED_PCT}${RESET}"
  printf " SHA-256 Checksum   : %s\n" "${CYAN}${SHA256_HASH}${RESET}"
  printf " Elapsed Time       : %s second(s)\n" "$DURATION"
  printf " History Log Entry  : %s\n" "$LOG_FILE"
  if [ "$REMOTE_ERRORS" -gt 0 ]; then
    printf " Remote Sync Status : ${RED}FAILED (${REMOTE_ERRORS} operation(s) failed)${RESET}\n"
  fi
  printf "${BOLD}%s${RESET}\n" "======================================================================"
fi

if [ "$REMOTE_ERRORS" -gt 0 ]; then
  exit 3
fi

exit 0
