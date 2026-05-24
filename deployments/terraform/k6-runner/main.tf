terraform {
  required_version = ">= 1.0"
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

# -------------------------------------------------------------------
# Data sources
# -------------------------------------------------------------------

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

data "aws_vpc" "default" {
  default = true
}

# -------------------------------------------------------------------
# Security Group
# -------------------------------------------------------------------

resource "aws_security_group" "k6_runner" {
  name        = "${var.project_name}-k6-runner"
  description = "Security group for k6 load test runner"
  vpc_id      = data.aws_vpc.default.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  # All outbound traffic allowed (for k6 to hit target)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name    = "${var.project_name}-k6-runner-sg"
    Project = var.project_name
  }
}

# -------------------------------------------------------------------
# Key Pair
# -------------------------------------------------------------------

resource "aws_key_pair" "k6_runner" {
  key_name   = "${var.project_name}-k6-runner-key"
  public_key = file(pathexpand(var.public_key_path))

  tags = {
    Name    = "${var.project_name}-k6-runner-key"
    Project = var.project_name
  }
}

# -------------------------------------------------------------------
# EC2 Instance
# -------------------------------------------------------------------

resource "aws_instance" "k6_runner" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.k6_runner.key_name
  vpc_security_group_ids = [aws_security_group.k6_runner.id]

  user_data = templatefile("${path.module}/user_data.sh", {
    repo_url = var.repo_url
    base_url = var.target_base_url
  })

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-k6-runner"
    Project = var.project_name
  }
}
