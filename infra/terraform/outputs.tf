output "nginx_proxy_public_ip" {
  description = "Public IP of nginx proxy"
  value       = aws_eip.nginx_proxy.public_ip
}

output "nginx_proxy_private_ip" {
  description = "Private IP of nginx proxy"
  value       = aws_instance.nginx_proxy.private_ip
}

output "java_service_public_ip" {
  description = "Public IP of Java 7 test service"
  value       = aws_eip.java_service.public_ip
}

output "java_service_private_ip" {
  description = "Private IP of Java service"
  value       = aws_instance.java_service.private_ip
}

output "ssh_commands" {
  description = "SSH commands to connect to instances"
  value = {
    nginx_proxy  = "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_eip.nginx_proxy.public_ip}"
    java_service = "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_eip.java_service.public_ip}"
  }
}

output "test_commands" {
  description = "Commands to test the setup"
  value = {
    nginx_health_check = "curl -k https://${aws_eip.nginx_proxy.public_ip}:443/health"
    java_users_api     = "curl http://${aws_eip.java_service.public_ip}:8080/api/users"
    java_orders_api    = "curl http://${aws_eip.java_service.public_ip}:8080/api/orders/1"
  }
}
