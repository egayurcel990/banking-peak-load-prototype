variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "banking-cloud-demo"
}

variable "app_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "k6_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "public_key_path" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

variable "repo_url" {
  type = string
}

variable "ssh_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "public_access_cidr" {
  type    = string
  default = "0.0.0.0/0"
}