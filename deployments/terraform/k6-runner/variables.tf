variable "aws_region" {
  description = "AWS region to deploy the k6 runner"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "banking-peak-load"
}

variable "instance_type" {
  description = "EC2 instance type for k6 runner"
  type        = string
  default     = "t3.medium" # 2 vCPU, 4GB RAM — cukup untuk 300 VUs
}

variable "public_key_path" {
  description = "Path to your SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "repo_url" {
  description = "Git repository URL to clone load test scripts from"
  type        = string
  default     = "https://github.com/egayurcel990/banking-peak-load-prototype.git"
}

variable "target_base_url" {
  description = "Base URL of the banking app to load test (e.g. http://<minikube-ip>:30080)"
  type        = string
  # Override this with your actual minikube/ngrok URL at apply time:
  # terraform apply -var="target_base_url=http://x.x.x.x:30080"
}
