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