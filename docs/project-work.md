# Part 2 - Provisioning Infrastructure Using Terraform

## What You're Building

```
Internet
    │
    ▼
[Public Subnet]
 Instance A  ← Vote (port 8080) + Result (port 8081) + Bastion Host
    │
    ▼ (private network only)
[Private Subnet 1]
 Instance B  ← Redis + Worker (.NET)
    │
    ▼
[Private Subnet 2]
 Instance C  ← PostgreSQL
```

**Why this layout?**
- A is public because users need to reach Vote and Result from the internet
- B and C are private because they should never be directly reachable — only A can talk to B, only B can talk to C
- A doubles as a **bastion host** — the only SSH entry point into the whole network

---

## Prerequisites

### 1. Check Terraform is installed
```bash
terraform -version
```
If not installed:
```bash
sudo snap install terraform --classic
```

### 2. Check AWS CLI is configured
```bash
aws sts get-caller-identity
```
If not configured:
```bash
aws configure
```
You'll need: Access Key ID, Secret Access Key, region (e.g. `us-east-1`).

### 3. Create an EC2 Key Pair (for SSH)
```bash
aws ec2 create-key-pair \
  --key-name voting-app-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/voting-app-key.pem

chmod 400 ~/.ssh/voting-app-key.pem
```
**Why:** EC2 instances don't use passwords — SSH key pairs are the only way in.

---

## Phase 1: Bootstrap — Remote State Storage

**Why do this first?** Terraform tracks what it created in a "state file." If you keep it locally and your machine dies, you lose track of your AWS resources. We store it in S3 (durable) with DynamoDB locking (so two people can't apply at the same time).

Create this file:

**`infra/bootstrap/main.tf`**
```hcl
provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "tf_state" {
  bucket = "voting-app-tfstate-${random_id.suffix.hex}"

  lifecycle {
    prevent_destroy = true
  }

  tags = { Name = "voting-app-terraform-state" }
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_dynamodb_table" "tf_locks" {
  name         = "voting-app-tf-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = { Name = "voting-app-tf-locks" }
}

output "s3_bucket_name" {
  value = aws_s3_bucket.tf_state.bucket
}
```

Run these commands:
```bash
cd infra/bootstrap
terraform init
terraform apply
```

**Copy the bucket name from the output** — you'll need it in Phase 2.

---

## Phase 2: Main Infrastructure

All files go in `infra/terraform/`. Create them one by one:

---

### `infra/terraform/variables.tf`
```hcl
variable "region" {
  default = "us-east-1"
}

variable "key_pair_name" {
  description = "Name of EC2 key pair"
  default     = "voting-app-key"
}
```

---

### `infra/terraform/backend.tf`

**Replace `YOUR_BUCKET_NAME` with the bucket name you copied from Phase 1.**

```hcl
terraform {
  backend "s3" {
    bucket         = "YOUR_BUCKET_NAME"
    key            = "voting-app/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "voting-app-tf-locks"
    encrypt        = true
  }
}
```

**Why:** This tells Terraform to store its state remotely instead of locally.

---

### `infra/terraform/main.tf`
```hcl
provider "aws" {
  region = var.region
}

# --- VPC ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "voting-app-vpc" }
}

# --- Subnets ---
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true
  tags = { Name = "voting-app-public" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.region}a"
  tags = { Name = "voting-app-private-b" }
}

resource "aws_subnet" "private_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.region}a"
  tags = { Name = "voting-app-private-c" }
}

# --- Internet Gateway (public subnet → internet) ---
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "voting-app-igw" }
}

# --- NAT Gateway (private subnets → internet for pulling Docker images) ---
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "voting-app-nat" }
}

# --- Route Tables ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "voting-app-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "voting-app-private-rt" }
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_c" {
  subnet_id      = aws_subnet.private_c.id
  route_table_id = aws_route_table.private.id
}
```

**Why the NAT Gateway?** Instances B and C are in private subnets with no direct internet route. They still need to pull Docker images and install packages. The NAT Gateway lets them initiate outbound connections through A's subnet without being reachable from the internet inbound. Note: NAT Gateways cost ~$0.045/hour — remember to `terraform destroy` when not in use.

---

### `infra/terraform/security_groups.tf`
```hcl
# Instance A — public-facing (Vote + Result + Bastion)
resource "aws_security_group" "vote_result" {
  name        = "vote-result-sg"
  description = "HTTP/HTTPS from internet, SSH bastion entry point"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Vote app"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Result app"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH (bastion)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "vote-result-sg" }
}

# Instance B — Redis + Worker (private)
resource "aws_security_group" "redis_worker" {
  name        = "redis-worker-sg"
  description = "Redis from Instance A only, SSH from bastion only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from vote/result"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.vote_result.id]
  }

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.vote_result.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "redis-worker-sg" }
}

# Instance C — PostgreSQL (private)
resource "aws_security_group" "postgres" {
  name        = "postgres-sg"
  description = "Postgres from Worker only, SSH from bastion only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres from worker"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.redis_worker.id]
  }

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.vote_result.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "postgres-sg" }
}
```

**Why source SG instead of CIDR?** Instead of hardcoding IP ranges (which change), we reference the security group itself. AWS automatically allows traffic from any instance in that SG — cleaner and more maintainable.

---

### `infra/terraform/ec2.tf`
```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  docker_user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ubuntu
  EOF
}

# Instance A — Vote + Result + Bastion (public)
resource "aws_instance" "instance_a" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.vote_result.id]
  user_data              = local.docker_user_data

  tags = { Name = "voting-app-A-frontend-bastion" }
}

# Instance B — Redis + Worker (private)
resource "aws_instance" "instance_b" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_b.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.redis_worker.id]
  user_data              = local.docker_user_data

  tags = { Name = "voting-app-B-redis-worker" }
}

# Instance C — PostgreSQL (private)
resource "aws_instance" "instance_c" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_c.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.postgres.id]
  user_data              = local.docker_user_data

  tags = { Name = "voting-app-C-postgres" }
}
```

---

### `infra/terraform/outputs.tf`
```hcl
output "instance_a_public_ip" {
  description = "SSH here first (Bastion). Vote: :8080, Result: :8081"
  value       = aws_instance.instance_a.public_ip
}

output "instance_b_private_ip" {
  description = "Redis + Worker (reach via bastion)"
  value       = aws_instance.instance_b.private_ip
}

output "instance_c_private_ip" {
  description = "PostgreSQL (reach via bastion)"
  value       = aws_instance.instance_c.private_ip
}
```

---

## Run It

```bash
cd infra/terraform
terraform init
terraform plan
terraform apply
```

`plan` shows you exactly what AWS resources will be created before spending any money. Review it, then `apply` to actually create them.

---

## Verify SSH Access

After apply, use the IPs from the output:
```bash
# SSH into Instance A (bastion)
ssh -i ~/.ssh/voting-app-key.pem ubuntu@<instance_a_public_ip>

# From inside A, hop to B
ssh -i ~/.ssh/voting-app-key.pem ubuntu@<instance_b_private_ip>

# From inside A, hop to C
ssh -i ~/.ssh/voting-app-key.pem ubuntu@<instance_c_private_ip>
```

To avoid copying the key onto Instance A, use SSH agent forwarding locally:
```bash
ssh-add ~/.ssh/voting-app-key.pem
ssh -A ubuntu@<instance_a_public_ip>
# Now hop to B/C without needing the key file on A
```

---

## Tear Down (when done)

```bash
terraform destroy
```

**Always run this when done with testing** — the NAT Gateway and EC2 instances cost money while running.
