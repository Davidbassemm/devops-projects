# DevOps Projects Portfolio

A curated collection of practical DevOps projects, system automation tools, CI/CD pipelines, container configurations, and infrastructure automation by **[David Bassem](https://github.com/Davidbassemm)**.

---

## Projects Catalog

| # | Project Name | Tech Stack | Status | Directory |
|---|:---|:---|:---:|:---|
| 01 | **Server Performance Stats** | Bash, Linux `/proc`, POSIX tools | Completed | [`server-stats/`](./server-stats/) |
| 02 | **Log Archive Tool** | Bash, POSIX `tar`/`gzip`, Cron/Systemd | Completed | [`log-archive/`](./log-archive/) |
| 03 | *Log Analyzer* | Bash, Python, RegEx | Planned | `log-analyzer/` |
| 04 | *CI/CD Pipeline Automation* | GitHub Actions, Docker | Planned | `cicd-automation/` |
| 05 | *Containerized Microservices* | Docker, Docker Compose | Planned | `container-apps/` |
| 06 | *Infrastructure as Code (IaC)* | Terraform, AWS / Cloud | Planned | `terraform-infra/` |

---

## Featured Projects

### 1. Server Performance Stats (`server-stats/`)
A zero-dependency Linux & macOS performance analysis tool inspired by the [roadmap.sh DevOps Project](https://roadmap.sh/projects/server-stats).
👉 **[View Project Documentation & Source Code](./server-stats/)**

### 2. Log Archive Tool (`log-archive/`)
A robust CLI utility that archives and compresses system logs into timestamped `tar.gz` archives, maintains audit history logs, verifies checksums, and manages automated retention and offsite backup sync. Inspired by the [roadmap.sh DevOps Project](https://roadmap.sh/projects/log-archive-tool).
👉 **[View Project Documentation & Source Code](./log-archive/)**

---

## Repository Structure

```text
devops-projects/
├── .gitignore
├── LICENSE
├── README.md
├── server-stats/
│   ├── README.md
│   └── server-stats.sh
└── log-archive/
    ├── README.md
    ├── log-archive.sh
    ├── log-archive
    ├── test_log_archive.sh
    └── examples/
        ├── cron-schedule.tab
        ├── log-archive.service
        └── log-archive.timer
```

---

## Author & Contact

- **Author**: David Bassem
- **GitHub**: [@Davidbassemm](https://github.com/Davidbassemm)
- **Email**: davidbassem694@gmail.com

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
