module "k3s_cluster" {
  source              = "../../blueprint"
  env                 = "dev"
  region              = "ap-southeast-1"
  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidr  = "10.0.1.0/24"
  private_subnet_cidr = "10.0.2.0/24"
  public_subnet_tags  = "public-sb"
  private_subnet_tags = "private-sb"
  ami                 = "ami-047126e50991d067b" #ubuntu 22.04
  nginx_instance_type = "t2.micro"
  k3s_instance_type   = "t2.micro"
  nginx_sg_name       = "nginx"
  k3s_sg_name         = "k3"
  k3s_worker_count    = 1
}


output "nginx_public_ip" {
  description = "The NGINX Load Balancer IP"
  value       = module.k3s_cluster.nginx_public_ip
}

output "nginx_public_dns" {
  description = "The NGINX Load Balancer DNS from the k3s cluster module"
  value       = module.k3s_cluster.nginx_public_dns
}

output "private_key_pem" {
  description = "private_key_pem"
  value       = module.k3s_cluster.private_key_pem
  sensitive   = true
}

output "public_key_fingerprint" {
  description = "public_key_fingerprint"
  value       = module.k3s_cluster.public_key_fingerprint
  sensitive   = true
}
