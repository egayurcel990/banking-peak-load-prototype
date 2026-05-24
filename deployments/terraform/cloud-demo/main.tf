terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "cloud_demo" {
  key_name   = "${var.project_name}-key"
  public_key = file(pathexpand(var.public_key_path))

  tags = {
    Name    = "${var.project_name}-key"
    Project = var.project_name
  }
}

resource "aws_security_group" "app_server" {
  name        = "${var.project_name}-app-sg"
  description = "App server security group"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  ingress {
    description = "Banking API"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.public_access_cidr]
  }

  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.public_access_cidr]
  }

  ingress {
    description = "Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.public_access_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-app-sg"
    Project = var.project_name
  }
}

resource "aws_security_group" "k6_runner" {
  name        = "${var.project_name}-k6-sg"
  description = "k6 runner security group"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-k6-sg"
    Project = var.project_name
  }
}

resource "aws_instance" "app_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.app_instance_type
  key_name                    = aws_key_pair.cloud_demo.key_name
  vpc_security_group_ids      = [aws_security_group.app_server.id]
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user_data_app.sh", {
    repo_url = var.repo_url
  })

  root_block_device {
    volume_size = 25
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-app-server"
    Project = var.project_name
  }
}

resource "aws_instance" "k6_runner" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.k6_instance_type
  key_name                    = aws_key_pair.cloud_demo.key_name
  vpc_security_group_ids      = [aws_security_group.k6_runner.id]
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user_data_k6.sh", {
    repo_url     = var.repo_url
    app_base_url = "http://${aws_instance.app_server.public_ip}:8080"
  })

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  depends_on = [aws_instance.app_server]

  tags = {
    Name    = "${var.project_name}-k6-runner"
    Project = var.project_name
  }
}