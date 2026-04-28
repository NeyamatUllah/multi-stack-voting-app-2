# Multi-Stack Voting App

A distributed voting application deployed on AWS using Terraform and Ansible. Users cast votes via a web UI; results update in real time.

## Architecture

```
                        Internet
                           │
                    ┌──────┴──────┐
                    │   Bastion   │  (SSH entry point only)
                    │100.48.90.x  │
                    └──────┬──────┘
                           │ SSH (ProxyJump)
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

## Tech Stack

| Service | Language / Image | Instance |
|---|---|---|
| Vote | Python / Flask | A |
| Result | Node.js / Express + Socket.io | A |
| Worker | C# / .NET 8 | B |
| Redis | `redis:alpine` | B |
| PostgreSQL | `postgres:15-alpine` | C |

## Project Structure

```
├── src/
│   ├── vote/           # Python Flask app
│   ├── result/         # Node.js result app
│   ├── worker/         # C# .NET worker
│   └── docker-compose.yml
├── infra/
│   ├── bootstrap/      # S3 + DynamoDB for Terraform remote state
│   ├── terraform/      # VPC, subnets, EC2, security groups
│   ├── ansible/        # Docker install + container deployment
│   └── scripts/
│       └── update-ssh-config.sh
└── docs/
    ├── project-work.md
    └── ansible-runbook.md
```

## Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform >= 1.3.0
- Ansible >= 2.16
- An EC2 key pair named `voting-app-key` in `us-east-1`
- Key file at `~/.ssh/voting-app-key.pem`
- Docker images pushed to DockerHub (`neyamat/vote`, `neyamat/result`, `neyamat/worker`)

## Deploy

### 1. Bootstrap remote state (once only)

```bash
cd infra/bootstrap
terraform init
terraform apply
```

### 2. Provision infrastructure

```bash
cd infra/terraform
terraform init
terraform apply
```

### 3. Refresh SSH config and Ansible vars

```bash
chmod +x infra/scripts/update-ssh-config.sh
./infra/scripts/update-ssh-config.sh
```

### 4. Deploy containers with Ansible

```bash
ansible-playbook -i infra/ansible/inventory.ini infra/ansible/playbook.yml
```

### 5. Verify

Get the public IP from Terraform outputs:
```bash
terraform -chdir=infra/terraform output instance_a_public_ip
```

- **Vote app**: `http://<instance_a_public_ip>:8080`
- **Result app**: `http://<instance_a_public_ip>:8081`

Cast a vote — a tick appears. The result app shows the count in real time.

## Re-deploy after destroy

```bash
cd infra/terraform && terraform destroy && terraform apply
./infra/scripts/update-ssh-config.sh
ansible-playbook -i infra/ansible/inventory.ini infra/ansible/playbook.yml
```

The script automatically updates `~/.ssh/config` and Ansible `group_vars` with new IPs.

## Security Group Design

| SG | Inbound |
|---|---|
| `bastion-sg` | Port 22 from `0.0.0.0/0` |
| `vote-result-sg` | Ports 8080, 8081 from internet; Port 22 from `bastion-sg` |
| `redis-worker-sg` | Port 6379 from `vote-result-sg`; Port 22 from `bastion-sg` |
| `postgres-sg` | Port 5432 from `redis-worker-sg` + `vote-result-sg`; Port 22 from `bastion-sg` |
