# Bastion Host — dedicated SSH entry point
resource "aws_security_group" "bastion" {
  name        = "bastion-sg"
  description = "SSH entry point from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from internet"
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

  tags = { Name = "bastion-sg" }
}

# Instance A — public-facing (Vote + Result)
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
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
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
    security_groups = [aws_security_group.bastion.id]
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
    description     = "Postgres from result app"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.vote_result.id]
  }

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "postgres-sg" }
}
