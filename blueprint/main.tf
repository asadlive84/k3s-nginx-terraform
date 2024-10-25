provider "aws" {
  region = var.region
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = var.env
  }
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ssh_key" {
  key_name   = "terraform-generated-key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "${var.env}-gw-NAT"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.public_subnet_tags}-public-subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.private_subnet_cidr
  tags = {
    Name = "${var.private_subnet_tags}-private-subnet"
  }
}

resource "aws_security_group" "nginx_sg" {
  name   = "${var.nginx_sg_name}-nginx-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] 
  }
}

resource "aws_security_group" "k3s_sg" {
  name   = "${var.k3s_sg_name}-k3s-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.nginx_sg.id] 
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
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
}

# Nginx Instance
resource "aws_instance" "nginx" {
  ami             = var.ami
  instance_type   = var.nginx_instance_type
  subnet_id       = aws_subnet.public.id
  security_groups = [aws_security_group.nginx_sg.id]
  key_name        = aws_key_pair.ssh_key.key_name

  tags = {
    Name = "${var.env}-nginx-load-balancer"
  }

  user_data = <<-EOF
  #!/bin/bash
  sudo apt update -y
  sudo apt install -y nginx
  sudo systemctl start nginx
  sudo systemctl enable nginx

  # Create the upstream block for K3s nodes
  echo 'upstream k3s_cluster {' | sudo tee /etc/nginx/sites-available/default
  %{ for ip in aws_instance.k3s_master[*].private_ip ~}
  echo "    server ${ip}:80;" | sudo tee -a /etc/nginx/sites-available/default
  %{ endfor ~}
  echo '}' | sudo tee -a /etc/nginx/sites-available/default

  # Nginx server block configuration
  echo '
  server {
      listen 80;

      location / {
          proxy_pass http://k3s_cluster;
          proxy_set_header Host \$host;
          proxy_set_header X-Real-IP \$remote_addr;
          proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto \$scheme;
      }
  }' | sudo tee -a /etc/nginx/sites-available/default

  # Reload Nginx to apply the new configuration
  sudo nginx -s reload
EOF

}

resource "aws_instance" "k3s_master" {
  count           = var.k3s_master_count
  ami             = var.ami
  instance_type   = var.k3s_instance_type
  subnet_id       = aws_subnet.private.id
  security_groups = [aws_security_group.k3s_sg.id]
  key_name        = aws_key_pair.ssh_key.key_name

  tags = {
    Name = "${var.env}-k3s-master-${count.index + 1}"
  }

  user_data = <<-EOF
    #!/bin/bash
    curl -sfL https://get.k3s.io | sh -
    echo "K3S_CLUSTER_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)" > /etc/k3s/token.txt
  EOF
}


resource "aws_instance" "k3s_worker" {
  count           = var.k3s_worker_count
  ami             = var.ami
  instance_type   = var.k3s_instance_type
  subnet_id       = aws_subnet.private.id
  security_groups = [aws_security_group.k3s_sg.id]
  key_name        = aws_key_pair.ssh_key.key_name

  tags = {
    Name = "${var.env}-k3s-worker-${count.index + 1}"
  }

  user_data = <<-EOF
    #!/bin/bash
    # Wait for the K3s master to be ready
    until curl -sfL https://\$(aws_instance.k3s_master[0].private_ip):6443; do
      echo "Waiting for K3s master to be ready..."
      sleep 5
    done

    # Retrieve the K3s token from the master node
    K3S_TOKEN=\$(curl -sfL https://\$(aws_instance.k3s_master[0].private_ip):6443/v1/namespaces/kube-system/services/k3s-server:443/proxy/node-token)

    # Print the token to a log file for debugging
    echo "K3S_TOKEN: \$K3S_TOKEN" > /tmp/k3s_token.log

    # Install K3s worker
    curl -sfL https://get.k3s.io | K3S_URL=https://\$(aws_instance.k3s_master[0].private_ip):6443 K3S_TOKEN=\$K3S_TOKEN sh -
  EOF
}



resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.env}-public-route-table"
  }
}

resource "aws_route_table_association" "public_association" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "${var.env}-private-route-table"
  }
}

resource "aws_route_table_association" "private_association" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private_rt.id
}


resource "local_file" "ssh_private_key" {
  content  = tls_private_key.ssh_key.private_key_pem
  filename = "${path.module}/id_rsa"
  file_permission = "0600"
}
