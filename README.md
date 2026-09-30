# DevOps Projects Portfolio

A curated collection of practical DevOps projects, system automation tools, CI/CD pipelines, container configurations, and infrastructure automation by **[David Bassem](https://github.com/Davidbassemm)**.

---

## Projects Catalog

| # | Project Name | Tech Stack | Status | Directory |
|---|:---|:---|:---:|:---|
| 01 | **Server Performance Stats** | Bash, Linux `/proc`, POSIX tools | Completed | [`server-stats/`](./server-stats/) |
| 02 | *Log Analyzer* | Bash, Python, RegEx | Planned | `log-analyzer/` |
| 03 | *CI/CD Pipeline Automation* | GitHub Actions, Docker | Planned | `cicd-automation/` |
| 04 | *Containerized Microservices* | Docker, Docker Compose | Planned | `container-apps/` |
| 05 | *Infrastructure as Code (IaC)* | Terraform, AWS / Cloud | Planned | `terraform-infra/` |

---

## Featured Project: Server Performance Stats (`server-stats/`)

A zero-dependency Linux & macOS performance analysis tool inspired by the [roadmap.sh DevOps Project](https://roadmap.sh/projects/server-stats).

### Key Features
- **CPU Metrics**: Real-time delta CPU utilization, idle rate, and colored visual progress bars.
- **Memory Metrics**: Total, Used, Free/Available RAM (MB/GB & percentages), Buffers/Cache, and Swap memory.
- **Disk Metrics**: Total physical storage vs. used/free percentages and root (`/`) mount details.
- **Process Profiling**: Top 5 processes sorted by CPU and Memory utilization.
- **System Telemetry**: OS distribution, architecture, uptime, load averages, logged-in sessions, and failed login audits.

👉 **[View Project Documentation & Source Code](./server-stats/)**

---

## Repository Structure

```text
devops-projects/
├── .gitignore
├── LICENSE
├── README.md
└── server-stats/
    ├── README.md
    └── server-stats.sh
```

---

## Author & Contact

- **Author**: David Bassem
- **GitHub**: [@Davidbassemm](https://github.com/Davidbassemm)
- **Email**: davidbassem694@gmail.com

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
