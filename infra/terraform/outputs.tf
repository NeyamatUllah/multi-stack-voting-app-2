output "bastion_public_ip" {
  description = "SSH entry point (dedicated bastion)"
  value       = aws_instance.bastion.public_ip
}

output "instance_a_public_ip" {
  description = "Vote: :8080, Result: :8081"
  value       = aws_instance.instance_a.public_ip
}

output "instance_a_private_ip" {
  description = "Instance A private IP (used for SSH via bastion)"
  value       = aws_instance.instance_a.private_ip
}

output "instance_b_private_ip" {
  description = "Redis + Worker (reach via bastion)"
  value       = aws_instance.instance_b.private_ip
}

output "instance_c_private_ip" {
  description = "PostgreSQL (reach via bastion)"
  value       = aws_instance.instance_c.private_ip
}
