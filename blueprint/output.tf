output "nginx_public_ip" {
  value       = aws_instance.nginx.public_ip
  description = "Public IP of the NGINX Load Balancer"
}


output "nginx_public_dns" {
  description = "The public DNS of the NGINX Load Balancer"
  value       = aws_instance.nginx.public_dns
}

output "private_key_pem" {
  value     = tls_private_key.ssh_key.private_key_pem
  sensitive = true
}

output "public_key_fingerprint" {
  value = aws_key_pair.ssh_key.fingerprint
  sensitive = true
}