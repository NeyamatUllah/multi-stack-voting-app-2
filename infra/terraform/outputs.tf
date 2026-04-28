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