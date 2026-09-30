# Server Performance & Resource Stats (`server-stats.sh`)

A lightweight, zero-dependency Bash script that monitors and analyzes essential server performance statistics on any Linux server (with native macOS support for local testing).

Inspired by the [roadmap.sh DevOps Project: Server Performance Stats](https://roadmap.sh/projects/server-stats).

---

## Features & Metrics Collected

### 1. Core Metrics
- **Total CPU Usage**: Real-time delta sampling calculated from `/proc/stat` (with `top` fallback), reporting used vs. idle percentages with a colored visual bar.
- **Total Memory Usage**: Free vs. Used RAM, available memory, buffer/cache, and percentage breakdown (with swap utilization).
- **Total Disk Usage**: Free vs. Used physical storage, percentage consumption, and root (`/`) mount details.
- **Top 5 Processes by CPU Usage**: PID, User, %CPU, %MEM, and Command.
- **Top 5 Processes by Memory Usage**: PID, User, %MEM, %CPU, and Command.

### 2. Stretch Goals
- **System Overview**: Hostname, OS Distribution (`/etc/os-release`), Architecture, and Kernel version.
- **Uptime & Load Average**: System uptime and 1-, 5-, and 15-minute load averages.
- **Logged-in Users**: Active session counts and distinct usernames.
- **Failed Login Attempts**: Detection of failed SSH/auth attempts via auth logs (`/var/log/auth.log`, `/var/log/secure`, `journalctl`, `lastb`).

---

## Zero Dependencies

The script relies solely on standard Linux POSIX tools and pseudo-filesystems:
- `bash` (v3.2+)
- `/proc/stat`, `/proc/meminfo`, `/proc/uptime`, `/proc/loadavg`
- `awk`, `grep`, `df`, `ps`

No external packages (`sysstat`, `bc`, `python`, etc.) are required.

---

## Quick Start

### Option 1: Run Directly via Git Clone

```bash
# Clone the repository
git clone git@github.com:Davidbassemm/server-stats.git
cd server-stats

# Make executable and run
chmod +x server-stats.sh
./server-stats.sh
```

### Option 2: Run via Curl (Remote Execution)

```bash
curl -sSL https://raw.githubusercontent.com/Davidbassemm/server-stats/main/server-stats.sh | bash
```

---

## Options & Flags

```text
Usage: server-stats.sh [OPTIONS]

OPTIONS:
  -h, --help      Display help message and exit
  --no-color      Disable colored ANSI terminal output
```

To run without color (e.g. for logging or piping to a file):
```bash
./server-stats.sh --no-color > server_report.txt
```

---

## Sample Output

```text
======================================================================
            SERVER PERFORMANCE & RESOURCE STATS                       
======================================================================
Timestamp: 2026-09-30 16:42:20 EEST

[+] SYSTEM OVERVIEW
  Hostname       : web-prod-01
  OS Distribution: Ubuntu 24.04 LTS (x86_64)
  Kernel Version : 6.8.0-31-generic
  System Uptime  : 14d 6h 32m
  Load Average   : 0.45, 0.58, 0.62 (1, 5, 15 min)
  Logged-in Users: 2 session(s) [david deployer]
  Failed Logins  : 0

[+] TOTAL CPU USAGE
  Usage Bar      : [████░░░░░░░░░░░░░░░░░░░░░]  16.5%
  Total Used     : 16.50%
  Total Idle     : 83.50%

[+] TOTAL MEMORY USAGE
  Usage Bar      : [████████████░░░░░░░░░░░░░]  48.2%
  Total RAM      : 16384 MB (16.00 GB)
  Used RAM       : 7897 MB (48.20%)
  Free/Available : 8487 MB (51.80%)
  Buffers/Cache  : 3412 MB
  Swap Usage     : 0 MB used / 2048 MB total (0.00% used)

[+] TOTAL DISK USAGE
  Usage Bar (Tot): [██████░░░░░░░░░░░░░░░░░░░]  24.1%
  Total Storage  : 200.00 GB
  Total Used     : 48.20 GB (24.10%)
  Total Free     : 151.80 GB (75.90%)
  Root (/) Mount : 48G used of 200G (Free: 152G, 25% used)

[+] TOP 5 PROCESSES BY CPU USAGE
PID      USER         %CPU     %MEM     COMMAND
------------------------------------------------------------
1024     nginx        14.2     1.5      nginx: worker process
1582     postgres      8.5     4.2      postgres: checkpointer
2110     node          6.1     8.4      node /app/server.js
412      systemd       0.8     0.2      /lib/systemd/systemd-journald
89       root          0.4     0.1      kcompactd0

[+] TOP 5 PROCESSES BY MEMORY USAGE
PID      USER         %MEM     %CPU     COMMAND
------------------------------------------------------------
2110     node          8.4     6.1      node /app/server.js
1582     postgres      4.2     8.5      postgres: checkpointer
1580     postgres      3.8     1.2      postgres: writer
1024     nginx         1.5    14.2      nginx: worker process
840      redis         1.1     0.2      redis-server *:6379

======================================================================
```

---

## Compatibility

Tested and compatible across:
- **Ubuntu** (20.04, 22.04, 24.04)
- **Debian** (11, 12)
- **CentOS / RHEL / Rocky / AlmaLinux** (8, 9)
- **Alpine Linux** (BusyBox compatible)
- **Amazon Linux** 2 & 2023
- **macOS** (Sonoma, Sequoia)

---

## License

MIT License. Free to use, adapt, and distribute.
