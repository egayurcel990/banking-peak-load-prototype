output "app_public_ip" {
  value = aws_instance.app_server.public_ip
}

output "k6_public_ip" {
  value = aws_instance.k6_runner.public_ip
}

output "api_url" {
  value = "http://${aws_instance.app_server.public_ip}:8080"
}

output "grafana_url" {
  value = "http://${aws_instance.app_server.public_ip}:3000"
}

output "prometheus_url" {
  value = "http://${aws_instance.app_server.public_ip}:9090"
}

output "ssh_app_command" {
  value = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.app_server.public_ip}"
}

output "ssh_k6_command" {
  value = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.k6_runner.public_ip}"
}

output "run_mixed_command" {
  value = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.k6_runner.public_ip} '/home/ubuntu/run-mixed.sh'"
}

output "run_status_command" {
  value = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.k6_runner.public_ip} '/home/ubuntu/run-status.sh'"
}
