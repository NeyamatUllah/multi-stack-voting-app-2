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

# Instance A — Vote + Result + Bastion (public)
resource "aws_instance" "instance_a" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.vote_result.id]

  tags = { Name = "voting-app-A-frontend-bastion" }
}

# Instance B — Redis + Worker (private)
resource "aws_instance" "instance_b" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_b.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.redis_worker.id]

  tags = { Name = "voting-app-B-redis-worker" }
}

# Instance C — PostgreSQL (private)
resource "aws_instance" "instance_c" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_c.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.postgres.id]

  tags = { Name = "voting-app-C-postgres" }
}
