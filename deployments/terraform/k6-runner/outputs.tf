output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.k6_runner.id
}

output "public_ip" {
  description = "Public IP of the k6 runner — use this to SSH in"
  value       = aws_instance.k6_runner.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to the k6 runner"
  value       = "ssh ubuntu@${aws_instance.k6_runner.public_ip}"
}

output "run_mixed_command" {
  description = "Command to run mixed load test from EC2"
  value       = "ssh ubuntu@${aws_instance.k6_runner.public_ip} 'cd banking-peak-load-prototype && BASE_URL=${var.target_base_url} k6 run scripts/load-test/mixed.js'"
}

output "estimated_cost" {
  description = "Estimated cost info"
  value       = "t3.medium = ~$0.04/hour. Remember to run 'terraform destroy' after demo!"
}
