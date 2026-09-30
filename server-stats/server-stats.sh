#!/usr/bin/env bash
# ==============================================================================
# server-stats.sh - Basic Server Performance & Resource Analyzer
# ------------------------------------------------------------------------------
# Analyzes and displays core server performance metrics:
#   - Total CPU usage
#   - Total Memory usage (Free vs. Used + percentage)
#   - Total Disk usage (Free vs. Used + percentage)
#   - Top 5 processes by CPU usage
#   - Top 5 processes by Memory usage
#   - Stretch metrics: OS version, Uptime, Load Average, Logged-in Users, Failed Logins
#
# Compatible with all major Linux distributions (Ubuntu, Debian, RHEL, CentOS,
# Fedora, Alpine, Amazon Linux, Arch) as well as macOS for local testing.
# ==============================================================================

set -u

# --- Color Configuration ---
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

# --- Visual Progress Bar ---
render_bar() {
  local raw_pct="${1:-0}"
  local int_pct="${raw_pct%.*}"
  [ -z "$int_pct" ] && int_pct=0
  [ "$int_pct" -gt 100 ] && int_pct=100
  [ "$int_pct" -lt 0 ] && int_pct=0

  local width=25
  local filled=$((int_pct * width / 100))
  local empty=$((width - filled))

  local bar_color="$GREEN"
  if [ "$int_pct" -ge 85 ]; then
    bar_color="$RED"
  elif [ "$int_pct" -ge 65 ]; then
    bar_color="$YELLOW"
  fi

  local bar=""
  local i=0
  while [ "$i" -lt "$filled" ]; do
    bar="${bar}█"
    i=$((i + 1))
  done
  i=0
  while [ "$i" -lt "$empty" ]; do
    bar="${bar}░"
    i=$((i + 1))
  done

  printf "${bar_color}[%s] %5.1f%%%s" "$bar" "$raw_pct" "$RESET"
}

# --- System & OS Information (Stretch Goal) ---
get_system_info() {
  HOSTNAME="$(hostname 2>/dev/null || uname -n)"
  DATE="$(date '+%Y-%m-%d %H:%M:%S %Z')"
  KERNEL="$(uname -r)"
  ARCH="$(uname -m)"
  OS_TYPE="$(uname -s)"

  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_NAME="${PRETTY_NAME:-${NAME:-Linux}}"
  elif command -v sw_vers >/dev/null 2>&1; then
    OS_NAME="$(sw_vers -productName) $(sw_vers -productVersion)"
  elif [ -f /etc/redhat-release ]; then
    OS_NAME="$(cat /etc/redhat-release)"
  elif [ -f /etc/issue ]; then
    OS_NAME="$(head -n 1 /etc/issue | tr -d '\r\n\\l')"
  else
    OS_NAME="$OS_TYPE"
  fi

  # Uptime & Load Average
  if [ -r /proc/uptime ] && [ -r /proc/loadavg ]; then
    uptime_seconds=$(cut -d. -f1 /proc/uptime)
    days=$((uptime_seconds / 86400))
    hours=$(((uptime_seconds % 86400) / 3600))
    minutes=$(((uptime_seconds % 3600) / 60))
    UPTIME="${days}d ${hours}h ${minutes}m"
    LOAD_AVG="$(awk '{print $1 ", " $2 ", " $3}' /proc/loadavg)"
  elif command -v uptime >/dev/null 2>&1; then
    raw_uptime="$(uptime)"
    UPTIME="$(echo "$raw_uptime" | sed -E 's/.*up +//; s/, +[0-9]+ users?.*//' | sed 's/^[ \t]*//')"
    LOAD_AVG="$(echo "$raw_uptime" | sed -E 's/.*load averages?: //')"
  else
    UPTIME="N/A"
    LOAD_AVG="N/A"
  fi

  # Logged-in Users
  if command -v who >/dev/null 2>&1; then
    LOGGED_USERS_COUNT=$(who 2>/dev/null | wc -l | tr -d ' ')
    LOGGED_USERS_LIST=$(who 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    [ -z "$LOGGED_USERS_LIST" ] && LOGGED_USERS_LIST="None"
  else
    LOGGED_USERS_COUNT="N/A"
    LOGGED_USERS_LIST="N/A"
  fi

  # Failed Login Attempts
  FAILED_LOGINS="0"
  if [ -r /var/log/auth.log ]; then
    FAILED_LOGINS=$(grep -s -E "Failed password|authentication failure" /var/log/auth.log 2>/dev/null | wc -l | tr -d ' ')
  elif [ -r /var/log/secure ]; then
    FAILED_LOGINS=$(grep -s -E "Failed password|authentication failure" /var/log/secure 2>/dev/null | wc -l | tr -d ' ')
  elif command -v journalctl >/dev/null 2>&1 && [ -w /run/systemd/journal ]; then
    FAILED_LOGINS=$(journalctl -u ssh -u sshd --since "yesterday" 2>/dev/null | grep -E "Failed password|authentication failure" 2>/dev/null | wc -l | tr -d ' ')
  elif command -v lastb >/dev/null 2>&1 && [ "$(id -u)" -eq 0 ]; then
    FAILED_LOGINS=$(lastb 2>/dev/null | grep -v "^$" | grep -v "^btmp" | wc -l | tr -d ' ')
  else
    if [ "$(id -u)" -ne 0 ]; then
      FAILED_LOGINS="Requires root/sudo to read auth logs"
    else
      FAILED_LOGINS="Log files not accessible"
    fi
  fi
}

# --- CPU Usage Calculation ---
get_cpu_usage() {
  CPU_USAGE="0.0"
  CPU_IDLE="100.0"

  if [ -r /proc/stat ]; then
    # Read two samples of /proc/stat separated by 0.5s for real-time accuracy
    read -r _ u1 n1 s1 i1 io1 ir1 sir1 st1 _ < /proc/stat
    sleep 0.5
    read -r _ u2 n2 s2 i2 io2 ir2 sir2 st2 _ < /proc/stat

    prev_idle=$((i1 + io1))
    curr_idle=$((i2 + io2))

    prev_non_idle=$((u1 + n1 + s1 + ir1 + sir1 + st1))
    curr_non_idle=$((u2 + n2 + s2 + ir2 + sir2 + st2))

    prev_total=$((prev_idle + prev_non_idle))
    curr_total=$((curr_idle + curr_non_idle))

    total_delta=$((curr_total - prev_total))
    idle_delta=$((curr_idle - prev_idle))

    if [ "$total_delta" -gt 0 ]; then
      CPU_USAGE=$(awk -v t="$total_delta" -v i="$idle_delta" 'BEGIN { printf "%.2f", ((t - i) * 100 / t) }')
      CPU_IDLE=$(awk -v t="$total_delta" -v i="$idle_delta" 'BEGIN { printf "%.2f", (i * 100 / t) }')
    fi
  elif [ "$OS_TYPE" = "Darwin" ]; then
    # macOS fallback
    top_stat=$(top -l 2 -n 0 -s 1 2>/dev/null | grep "CPU usage" | tail -n 1)
    if [ -n "$top_stat" ]; then
      u_val=$(echo "$top_stat" | awk '{print $3}' | tr -d '%')
      s_val=$(echo "$top_stat" | awk '{print $5}' | tr -d '%')
      i_val=$(echo "$top_stat" | awk '{print $7}' | tr -d '%')
      CPU_USAGE=$(awk -v u="$u_val" -v s="$s_val" 'BEGIN { printf "%.2f", u + s }')
      CPU_IDLE="$i_val"
    fi
  elif command -v top >/dev/null 2>&1; then
    # Linux top fallback
    top_line=$(top -bn2 -d 0.5 2>/dev/null | grep -i "%cpu" | tail -n 1)
    idle_val=$(echo "$top_line" | awk '{for(i=1;i<=NF;i++) if($i ~ /id/){print $(i-1)}}' | tr -d 'id,%')
    if [ -n "$idle_val" ]; then
      CPU_IDLE="$idle_val"
      CPU_USAGE=$(awk -v i="$idle_val" 'BEGIN { printf "%.2f", 100 - i }')
    fi
  fi
}

# --- Memory Usage Calculation ---
get_memory_usage() {
  MEM_TOTAL_MB=0
  MEM_USED_MB=0
  MEM_FREE_MB=0
  MEM_BUFFERS_CACHE_MB=0
  MEM_USED_PCT=0.0
  MEM_FREE_PCT=100.0

  SWAP_TOTAL_MB=0
  SWAP_USED_MB=0
  SWAP_FREE_MB=0
  SWAP_USED_PCT=0.0

  if [ -r /proc/meminfo ]; then
    total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    free_kb=$(awk '/^MemFree:/ {print $2}' /proc/meminfo)
    avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
    buffers_kb=$(awk '/^Buffers:/ {print $2}' /proc/meminfo)
    cached_kb=$(awk '/^Cached:/ {print $2}' /proc/meminfo)
    swap_total_kb=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
    swap_free_kb=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo)

    total_kb=${total_kb:-0}
    free_kb=${free_kb:-0}
    buffers_kb=${buffers_kb:-0}
    cached_kb=${cached_kb:-0}
    swap_total_kb=${swap_total_kb:-0}
    swap_free_kb=${swap_free_kb:-0}

    if [ -n "$avail_kb" ] && [ "$avail_kb" -gt 0 ]; then
      used_kb=$((total_kb - avail_kb))
      free_effective_kb=$avail_kb
    else
      free_effective_kb=$((free_kb + buffers_kb + cached_kb))
      used_kb=$((total_kb - free_effective_kb))
    fi

    MEM_TOTAL_MB=$((total_kb / 1024))
    MEM_USED_MB=$((used_kb / 1024))
    MEM_FREE_MB=$((free_effective_kb / 1024))
    MEM_BUFFERS_CACHE_MB=$(((buffers_kb + cached_kb) / 1024))

    if [ "$total_kb" -gt 0 ]; then
      MEM_USED_PCT=$(awk -v u="$used_kb" -v t="$total_kb" 'BEGIN { printf "%.2f", (u * 100 / t) }')
      MEM_FREE_PCT=$(awk -v f="$free_effective_kb" -v t="$total_kb" 'BEGIN { printf "%.2f", (f * 100 / t) }')
    fi

    SWAP_TOTAL_MB=$((swap_total_kb / 1024))
    swap_used_kb=$((swap_total_kb - swap_free_kb))
    SWAP_USED_MB=$((swap_used_kb / 1024))
    SWAP_FREE_MB=$((swap_free_kb / 1024))
    if [ "$swap_total_kb" -gt 0 ]; then
      SWAP_USED_PCT=$(awk -v u="$swap_used_kb" -v t="$swap_total_kb" 'BEGIN { printf "%.2f", (u * 100 / t) }')
    fi
  elif [ "$OS_TYPE" = "Darwin" ]; then
    # macOS fallback using sysctl and vm_stat
    total_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
    MEM_TOTAL_MB=$((total_bytes / 1024 / 1024))
    page_size=$(vm_stat 2>/dev/null | awk '/page size of/ {print $8}')
    page_size=${page_size:-4096}

    p_free=$(vm_stat 2>/dev/null | awk '/Pages free:/ {print $3}' | tr -d '.')
    p_spec=$(vm_stat 2>/dev/null | awk '/Pages speculative:/ {print $3}' | tr -d '.')
    p_active=$(vm_stat 2>/dev/null | awk '/Pages active:/ {print $3}' | tr -d '.')
    p_inactive=$(vm_stat 2>/dev/null | awk '/Pages inactive:/ {print $3}' | tr -d '.')
    p_wired=$(vm_stat 2>/dev/null | awk '/Pages wired down:/ {print $4}' | tr -d '.')
    p_comp=$(vm_stat 2>/dev/null | awk '/Pages occupied by compressor:/ {print $5}' | tr -d '.')

    p_free=${p_free:-0}; p_spec=${p_spec:-0}; p_active=${p_active:-0}
    p_inactive=${p_inactive:-0}; p_wired=${p_wired:-0}; p_comp=${p_comp:-0}

    free_bytes=$(((p_free + p_spec) * page_size))
    used_bytes=$(((p_active + p_wired + p_comp) * page_size))
    cache_bytes=$((p_inactive * page_size))

    MEM_USED_MB=$((used_bytes / 1024 / 1024))
    MEM_FREE_MB=$((free_bytes / 1024 / 1024))
    MEM_BUFFERS_CACHE_MB=$((cache_bytes / 1024 / 1024))

    if [ "$MEM_TOTAL_MB" -gt 0 ]; then
      MEM_USED_PCT=$(awk -v u="$MEM_USED_MB" -v t="$MEM_TOTAL_MB" 'BEGIN { printf "%.2f", (u * 100 / t) }')
      MEM_FREE_PCT=$(awk -v f="$MEM_FREE_MB" -v t="$MEM_TOTAL_MB" 'BEGIN { printf "%.2f", (f * 100 / t) }')
    fi
  elif command -v free >/dev/null 2>&1; then
    # Standard free -m fallback
    read -r m_tot m_used m_free m_buff m_avail <<< "$(free -m 2>/dev/null | awk '/^Mem:/ {print $2, $3, $4, $6, $7}')"
    MEM_TOTAL_MB=${m_tot:-0}
    MEM_USED_MB=${m_used:-0}
    MEM_BUFFERS_CACHE_MB=${m_buff:-0}
    if [ -n "$m_avail" ] && [ "$m_avail" -gt 0 ]; then
      MEM_FREE_MB=$m_avail
    else
      MEM_FREE_MB=$((m_free + m_buff))
    fi
    if [ "$MEM_TOTAL_MB" -gt 0 ]; then
      MEM_USED_PCT=$(awk -v u="$MEM_USED_MB" -v t="$MEM_TOTAL_MB" 'BEGIN { printf "%.2f", (u * 100 / t) }')
      MEM_FREE_PCT=$(awk -v f="$MEM_FREE_MB" -v t="$MEM_TOTAL_MB" 'BEGIN { printf "%.2f", (f * 100 / t) }')
    fi
  fi
}

# --- Disk Usage Calculation ---
get_disk_usage() {
  # Root Filesystem (/)
  read -r ROOT_FS ROOT_TOTAL_H ROOT_USED_H ROOT_AVAIL_H ROOT_PCT_RAW < <(df -Ph / 2>/dev/null | awk 'NR==2 {print $1, $2, $3, $4, $5}')
  ROOT_PCT=$(echo "${ROOT_PCT_RAW:-0}" | tr -d '%')
  ROOT_FREE_PCT=$(awk -v u="$ROOT_PCT" 'BEGIN { printf "%.1f", 100 - u }')

  # Total storage calculation across physical filesystems
  if [ "$OS_TYPE" = "Darwin" ]; then
    read -r DISK_TOTAL_MB DISK_USED_MB DISK_AVAIL_MB < <(df -Pm / 2>/dev/null | awk 'NR==2 {print $2, $3, $4}')
  else
    # Exclude virtual filesystems on Linux
    read -r DISK_TOTAL_MB DISK_USED_MB DISK_AVAIL_MB < <(df -Pm -x tmpfs -x devtmpfs -x squashfs -x overlay -x iso9660 2>/dev/null | awk 'NR>1 {tot += $2; used += $3; free += $4} END {print tot, used, free}')
    if [ -z "$DISK_TOTAL_MB" ] || [ "$DISK_TOTAL_MB" = "0" ]; then
      read -r DISK_TOTAL_MB DISK_USED_MB DISK_AVAIL_MB < <(df -Pm / 2>/dev/null | awk 'NR==2 {print $2, $3, $4}')
    fi
  fi

  DISK_TOTAL_MB=${DISK_TOTAL_MB:-0}
  DISK_USED_MB=${DISK_USED_MB:-0}
  DISK_AVAIL_MB=${DISK_AVAIL_MB:-0}

  if [ "$DISK_TOTAL_MB" -gt 0 ]; then
    TOTAL_DISK_GB=$(awk -v m="$DISK_TOTAL_MB" 'BEGIN { printf "%.2f GB", m / 1024 }')
    USED_DISK_GB=$(awk -v m="$DISK_USED_MB" 'BEGIN { printf "%.2f GB", m / 1024 }')
    AVAIL_DISK_GB=$(awk -v m="$DISK_AVAIL_MB" 'BEGIN { printf "%.2f GB", m / 1024 }')
    TOTAL_DISK_USED_PCT=$(awk -v u="$DISK_USED_MB" -v t="$DISK_TOTAL_MB" 'BEGIN { printf "%.2f", (u * 100 / t) }')
    TOTAL_DISK_FREE_PCT=$(awk -v a="$DISK_AVAIL_MB" -v t="$DISK_TOTAL_MB" 'BEGIN { printf "%.2f", (a * 100 / t) }')
  else
    TOTAL_DISK_GB="N/A"
    USED_DISK_GB="N/A"
    AVAIL_DISK_GB="N/A"
    TOTAL_DISK_USED_PCT="0.0"
    TOTAL_DISK_FREE_PCT="0.0"
  fi
}

# --- Top 5 Processes by CPU ---
show_top_cpu_processes() {
  printf "${BOLD}%-8s %-12s %-8s %-8s %s${RESET}\n" "PID" "USER" "%CPU" "%MEM" "COMMAND"
  printf "%s\n" "${DIM}------------------------------------------------------------${RESET}"

  if [ "$OS_TYPE" = "Darwin" ]; then
    ps -A -o pid,user,%cpu,%mem,comm -r 2>/dev/null | tail -n +2 | head -n 5 | while read -r pid usr cpu mem cmd; do
      printf "%-8s %-12s %-8s %-8s %s\n" "$pid" "$usr" "$cpu" "$mem" "$cmd"
    done
  elif ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu >/dev/null 2>&1; then
    ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu 2>/dev/null | tail -n +2 | head -n 5 | while read -r pid usr cpu mem cmd; do
      printf "%-8s %-12s %-8s %-8s %s\n" "$pid" "$usr" "$cpu" "$mem" "$cmd"
    done
  else
    # Portable fallback for Busybox / minimal Linux
    ps -eo pid,user,%cpu,%mem,comm 2>/dev/null | tail -n +2 | sort -k3 -nr | head -n 5 | while read -r pid usr cpu mem cmd; do
      printf "%-8s %-12s %-8s %-8s %s\n" "$pid" "$usr" "$cpu" "$mem" "$cmd"
    done
  fi
}

# --- Top 5 Processes by Memory ---
show_top_mem_processes() {
  printf "${BOLD}%-8s %-12s %-8s %-8s %s${RESET}\n" "PID" "USER" "%MEM" "%CPU" "COMMAND"
  printf "%s\n" "${DIM}------------------------------------------------------------${RESET}"

  if [ "$OS_TYPE" = "Darwin" ]; then
    ps -A -o pid,user,%mem,%cpu,comm -m 2>/dev/null | tail -n +2 | head -n 5 | while read -r pid usr mem cpu cmd; do
      printf "%-8s %-12s %-8s %-8s %s\n" "$pid" "$usr" "$mem" "$cpu" "$cmd"
    done
  elif ps -eo pid,user,%mem,%cpu,comm --sort=-%mem >/dev/null 2>&1; then
    ps -eo pid,user,%mem,%cpu,comm --sort=-%mem 2>/dev/null | tail -n +2 | head -n 5 | while read -r pid usr mem cpu cmd; do
      printf "%-8s %-12s %-8s %-8s %s\n" "$pid" "$usr" "$mem" "$cpu" "$cmd"
    done
  else
    # Portable fallback for Busybox / minimal Linux
    ps -eo pid,user,%mem,%cpu,comm 2>/dev/null | tail -n +2 | sort -k3 -nr | head -n 5 | while read -r pid usr mem cpu cmd; do
      printf "%-8s %-12s %-8s %-8s %s\n" "$pid" "$usr" "$mem" "$cpu" "$cmd"
    done
  fi
}

# --- Display Output ---
print_report() {
  echo ""
  printf "${BLUE}======================================================================${RESET}\n"
  printf "${BOLD}${CYAN}            SERVER PERFORMANCE & RESOURCE STATS                       ${RESET}\n"
  printf "${BLUE}======================================================================${RESET}\n"
  printf "${DIM}Timestamp: %s${RESET}\n" "$DATE"
  echo ""

  # Section 1: System Info
  printf "${MAGENTA}[+] SYSTEM OVERVIEW${RESET}\n"
  printf "  ${BOLD}Hostname       :${RESET} %s\n" "$HOSTNAME"
  printf "  ${BOLD}OS Distribution:${RESET} %s (%s)\n" "$OS_NAME" "$ARCH"
  printf "  ${BOLD}Kernel Version :${RESET} %s\n" "$KERNEL"
  printf "  ${BOLD}System Uptime  :${RESET} %s\n" "$UPTIME"
  printf "  ${BOLD}Load Average   :${RESET} %s (1, 5, 15 min)\n" "$LOAD_AVG"
  printf "  ${BOLD}Logged-in Users:${RESET} %s session(s) [%s]\n" "$LOGGED_USERS_COUNT" "$LOGGED_USERS_LIST"
  printf "  ${BOLD}Failed Logins  :${RESET} %s\n" "$FAILED_LOGINS"
  echo ""

  # Section 2: CPU Usage
  printf "${MAGENTA}[+] TOTAL CPU USAGE${RESET}\n"
  printf "  ${BOLD}Usage Bar      :${RESET} %s\n" "$(render_bar "$CPU_USAGE")"
  printf "  ${BOLD}Total Used     :${RESET} %s%%\n" "$CPU_USAGE"
  printf "  ${BOLD}Total Idle     :${RESET} %s%%\n" "$CPU_IDLE"
  echo ""

  # Section 3: Memory Usage
  printf "${MAGENTA}[+] TOTAL MEMORY USAGE${RESET}\n"
  printf "  ${BOLD}Usage Bar      :${RESET} %s\n" "$(render_bar "$MEM_USED_PCT")"
  printf "  ${BOLD}Total RAM      :${RESET} %s MB (%.2f GB)\n" "$MEM_TOTAL_MB" "$(awk -v m="$MEM_TOTAL_MB" 'BEGIN { printf "%.2f", m / 1024 }')"
  printf "  ${BOLD}Used RAM       :${RESET} %s MB (%s%%)\n" "$MEM_USED_MB" "$MEM_USED_PCT"
  printf "  ${BOLD}Free/Available :${RESET} %s MB (%s%%)\n" "$MEM_FREE_MB" "$MEM_FREE_PCT"
  printf "  ${BOLD}Buffers/Cache  :${RESET} %s MB\n" "$MEM_BUFFERS_CACHE_MB"
  if [ "$SWAP_TOTAL_MB" -gt 0 ]; then
    printf "  ${BOLD}Swap Usage     :${RESET} %s MB used / %s MB total (%s%% used)\n" "$SWAP_USED_MB" "$SWAP_TOTAL_MB" "$SWAP_USED_PCT"
  fi
  echo ""

  # Section 4: Disk Usage
  printf "${MAGENTA}[+] TOTAL DISK USAGE${RESET}\n"
  printf "  ${BOLD}Usage Bar (Tot):${RESET} %s\n" "$(render_bar "$TOTAL_DISK_USED_PCT")"
  printf "  ${BOLD}Total Storage  :${RESET} %s\n" "$TOTAL_DISK_GB"
  printf "  ${BOLD}Total Used     :${RESET} %s (%s%%)\n" "$USED_DISK_GB" "$TOTAL_DISK_USED_PCT"
  printf "  ${BOLD}Total Free     :${RESET} %s (%s%%)\n" "$AVAIL_DISK_GB" "$TOTAL_DISK_FREE_PCT"
  printf "  ${BOLD}Root (/) Mount :${RESET} %s used of %s (Free: %s, %s%% used)\n" "$ROOT_USED_H" "$ROOT_TOTAL_H" "$ROOT_AVAIL_H" "$ROOT_PCT"
  echo ""

  # Section 5: Top 5 CPU Processes
  printf "${MAGENTA}[+] TOP 5 PROCESSES BY CPU USAGE${RESET}\n"
  show_top_cpu_processes
  echo ""

  # Section 6: Top 5 Memory Processes
  printf "${MAGENTA}[+] TOP 5 PROCESSES BY MEMORY USAGE${RESET}\n"
  show_top_mem_processes
  echo ""

  printf "${BLUE}======================================================================${RESET}\n"
}

# --- CLI Argument Parsing ---
show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Analyze basic server performance stats across Linux distributions and macOS.

OPTIONS:
  -h, --help      Display this help message and exit
  --no-color      Disable colored ANSI terminal output

METRICS REPORTED:
  1. Total CPU usage & idle percentage
  2. Total Memory usage (Used vs. Free with percentages and visual bars)
  3. Total Disk usage (Used vs. Free with percentages and root mount summary)
  4. Top 5 processes by CPU consumption
  5. Top 5 processes by Memory consumption
  6. Stretch goals: OS version, Uptime, Load Average, Active users, Failed logins
EOF
  exit 0
}

# --- Main Entrypoint ---
main() {
  for arg in "$@"; do
    case "$arg" in
      -h|--help)
        show_help
        ;;
      --no-color)
        NO_COLOR=1
        ;;
      *)
        echo "Error: Unknown option '$arg'" >&2
        echo "Run '$(basename "$0") --help' for usage instructions." >&2
        exit 1
        ;;
    esac
  done

  setup_colors
  get_system_info
  get_cpu_usage
  get_memory_usage
  get_disk_usage
  print_report
}

main "$@"
