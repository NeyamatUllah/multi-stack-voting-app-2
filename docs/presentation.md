---
marp: true
theme: default
paginate: true
style: |
  section {
    font-family: 'Segoe UI', sans-serif;
  }
  h1 { color: #2c3e50; }
  h2 { color: #2980b9; }
  code { background: #f4f4f4; padding: 2px 6px; border-radius: 4px; }
  table { width: 100%; }
  th { background: #2980b9; color: white; }
---

# Multi-Stack Voting App
### End-to-End DevOps Project

**Neyamatullah**
Ironhack Bootcamp — 2026

---

## Project Overview

A distributed voting application built with **5 different technologies**, deployed on **AWS** using Infrastructure as Code and Configuration Management.

> Users cast a vote → Worker processes it → Result updates in real time

**Three Parts:**
1. Local development with Docker
2. Cloud infrastructure with Terraform
3. Automated deployment with Ansible

---

## Application Architecture

```
                        Internet
                           │
                    ┌──────┴──────┐
                    │   Bastion   │  SSH entry point only
                    └──────┬──────┘
                           │ ProxyJump
          ┌────────────────┼────────────────┐
          │                │                │
   ┌──────┴──────┐  ┌──────┴──────┐  ┌──────┴──────┐
   │ Instance A  │  │ Instance B  │  │ Instance C  │
   │  (public)   │  │  (private)  │  │  (private)  │
   │─────────────│  │─────────────│  │─────────────│
   │ vote  :8080 │  │ redis :6379 │  │postgres:5432│
   │result :8081 │  │ worker      │  │             │
   └─────────────┘  └─────────────┘  └─────────────┘
```

---

## Tech Stack

| Service | Technology | Role |
|---|---|---|
| **Vote** | Python / Flask | Accepts votes → pushes to Redis |
| **Result** | Node.js / Socket.io | Reads PostgreSQL → live updates |
| **Worker** | C# / .NET 8 | Reads Redis → writes to PostgreSQL |
| **Redis** | redis:alpine | Vote queue |
| **PostgreSQL** | postgres:15-alpine | Persistent vote storage |

---

## Part 1 — Local Development

**Goal:** Run all 5 services locally with Docker Compose

**Key change:** Modified `docker-compose.yml` to build from local Dockerfiles instead of pre-built images

```yaml
vote:
  build:
    context: ./vote
    target: final    # multi-stage build

result:
  build: ./result

worker:
  build: ./worker
```

**Result:** Full app running locally at `localhost:8080` and `localhost:8081`

---

## Part 2 — AWS Infrastructure (Terraform)

**4 EC2 instances** on Ubuntu 22.04 in a custom VPC:

| Instance | Role | Subnet |
|---|---|---|
| Bastion | SSH entry point | Public |
| A | Vote + Result apps | Public |
| B | Redis + Worker | Private |
| C | PostgreSQL | Private |

**Remote state** stored in S3 + DynamoDB lock (bootstrap pattern)

---

## Network Design

```
VPC: 10.0.0.0/16
│
├── Public Subnet (10.0.1.0/24)
│   ├── Bastion
│   └── Instance A (Vote + Result)
│       └── Internet Gateway → internet
│
├── Private Subnet B (10.0.2.0/24)
│   └── Instance B (Redis + Worker)
│       └── NAT Gateway → Docker Hub pulls
│
└── Private Subnet C (10.0.3.0/24)
    └── Instance C (PostgreSQL)
        └── NAT Gateway → Docker Hub pulls
```

---

## Security Group Design (Least Privilege)

| Security Group | Allowed Inbound |
|---|---|
| `bastion-sg` | Port 22 from internet |
| `vote-result-sg` | Ports 8080/8081 from internet; Port 22 from `bastion-sg` only |
| `redis-worker-sg` | Port 6379 from `vote-result-sg`; Port 22 from `bastion-sg` only |
| `postgres-sg` | Port 5432 from `redis-worker-sg` + `vote-result-sg`; Port 22 from `bastion-sg` only |

No open ports to the internet except what is strictly needed.

---

## Part 3 — Ansible Deployment

**One command deploys everything in order:**

```bash
ansible-playbook -i infra/ansible/inventory.ini infra/ansible/playbook.yml
```

**4 plays in sequence:**
1. Install Docker CE on all app instances (A, B, C)
2. Deploy PostgreSQL on Instance C
3. Deploy Redis + Worker on Instance B
4. Deploy Vote + Result on Instance A

---

## Automation Script

After every `terraform apply`, one script refreshes everything:

```bash
./infra/scripts/update-ssh-config.sh
```

**What it does:**
- Reads new IPs from `terraform output`
- Updates `~/.ssh/config` with new host aliases + ProxyJump
- Updates Ansible `group_vars` with new private IPs

**Full re-deploy workflow:**
```bash
terraform apply
./infra/scripts/update-ssh-config.sh
ansible-playbook -i infra/ansible/inventory.ini infra/ansible/playbook.yml
```

---

## Add-Ons Implemented

| Add-On | Status | What was done |
|---|---|---|
| Proper Security Groups | Done | SG-to-SG rules, no open CIDRs |
| Remote State (S3 + DynamoDB) | Done | Bootstrap pattern with separate folder |
| PostgreSQL Volume | Done | Named Docker volume persists data |
| Dedicated Bastion Host | Done | 4th EC2, all SSH routes through it |

---

## Bug Found & Fixed

**Problem:** Result app showed no votes even though voting worked.

**Root cause:** Security group for PostgreSQL (Instance C) only allowed connections from `redis-worker-sg` (Instance B). The result app on Instance A had no access to PostgreSQL.

**Fix:** Added ingress rule to `postgres-sg` allowing port 5432 from `vote-result-sg`

```hcl
ingress {
  from_port       = 5432
  to_port         = 5432
  protocol        = "tcp"
  security_groups = [aws_security_group.vote_result.id]
}
```

---

## Key Learnings

- **Terraform** provisions infrastructure; **Ansible** configures software — keep them separate
- Security group `description` is **immutable** in AWS — changing it forces destroy + recreate
- `user_data` gives no visibility into success/failure — Ansible is better for software install
- `<<-EOF` heredoc in Terraform strips leading whitespace based on closing marker indentation
- Git ignores patterns with leading spaces — patterns must start at column 0
- ProxyJump SSH config uses **private IPs** for instances behind the bastion, not public IPs

---

## Demo

- **Vote app:** `http://<instance_a_public_ip>:8080`
- **Result app:** `http://<instance_a_public_ip>:8081`

**Repository:** https://github.com/NeyamatUllah/multi-stack-voting-app-2

---

# Thank You

**Neyamat Ullah**

Questions?
