variable "region" {
  type = string
}


variable "vpc_cidr" {
  type = string
}
variable "env" {
  type = string
}


variable "public_subnet_cidr" {
  type = string
}
variable "private_subnet_cidr" {
  type = string
}


variable "public_subnet_tags" {
  type = string
}
variable "private_subnet_tags" {
  type = string
}
variable "nginx_sg_name" {
  type = string
}
variable "k3s_sg_name" {
  type = string
}
variable "ami" {
  type = string
}

variable "nginx_instance_type" {
  type = string
}
variable "k3s_instance_type" {
  type = string
}

variable "k3s_master_count" {
  default = 1
  type = number
}

variable "k3s_worker_count" {
  default = 1
  type = number
}