# Part 3 — Ansible Deployment Runbook

## Environment Variables (confirmed from source)

| Service | Key Vars |
|---|---|
| **PostgreSQL** (Instance C) | `POSTGRES_USER=postgres` `POSTGRES_PASSWORD=postgres` |
| **Redis** (Instance B) | none |
| **Worker** (Instance B) | `REDIS_HOST=10.0.2.152` `DB_HOST=10.0.3.201` `DB_USERNAME=postgres` `DB_PASSWORD=postgres` `DB_NAME=postgres` |
| **Vote** (Instance A) | `REDIS_HOST=10.0.2.152` |
| **Result** (Instance A) | `PG_HOST=10.0.3.201` `PG_USER=postgres` `PG_PASSWORD=postgres` `PG_DATABASE=postgres` |

---

## Step 1 — SSH Config (auto-generated from Terraform)

The script at `infra/scripts/update-ssh-config.sh` reads IPs from `terraform output`
and writes the SSH config block automatically. Run it after every `terraform apply`.

```bash
# Make executable once
chmod +x infra/scripts/update-ssh-config.sh

# Run after every terraform apply
./infra/scripts/update-ssh-config.sh
```

If your key is not at `~/.ssh/voting-app-key.pem`, override it:
```bash
SSH_KEY_FILE=~/.ssh/your-key.pem ./infra/scripts/update-ssh-config.sh
```

Verify with: `ssh backend-instance-1` and `ssh db-instance-1`

---

## Step 2 — Install Ansible (local machine)

```bash
sudo apt update && sudo apt install -y ansible
ansible --version
```

---

## Step 3 — Create Ansible Files

Files to create in `infra/ansible/`:

```
infra/ansible/
├── inventory.ini
├── playbook.yml
└── group_vars/
    ├── frontend.yml
    ├── backend.yml
    └── db.yml
```

Each play targets one host group and runs the correct containers via `docker run` shell commands.
No extra dependencies needed on EC2 since Docker CE is already installed via user_data.

---

## Step 4 — Run Playbook

```bash
ansible-playbook -i infra/ansible/inventory.ini infra/ansible/playbook.yml
```

---

## Step 5 — Verify

- Vote app: `http://3.235.169.102:8080` — cast a vote, tick appears
- Result app: `http://3.235.169.102:8081` — vote count appears bottom-right

---

## Instance IP Reference

| Instance | Role | IP |
|---|---|---|
| A | Vote + Result + Bastion | `3.235.169.102` (public) |
| B | Redis + Worker | `10.0.2.152` (private) |
| C | PostgreSQL | `10.0.3.201` (private) |

## DockerHub Images

| Service | Image |
|---|---|
| vote | `neyamat/vote:latest` |
| result | `neyamat/result:latest` |
| worker | `neyamat/worker:latest` |
| redis | `redis:alpine` |
| postgres | `postgres:15-alpine` |
