variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-west-2"
}

variable "key_pair_name" {
  description = "Name of existing EC2 key pair for SSH access"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Restrict this in production!
}

variable "nginx_instance_type" {
  description = "EC2 instance type for nginx proxy"
  type        = string
  default     = "t3.small"  # 2 vCPU, 2GB RAM
}

variable "java_instance_type" {
  description = "EC2 instance type for Java service"
  type        = string
  default     = "t3.small"  # 2 vCPU, 2GB RAM
}

variable "observe_token" {
  description = "Observe datastream token"
  type        = string
  sensitive   = true
}

variable "observe_endpoint_host" {
  description = "Observe HTTP ingest endpoint hostname (without https://)"
  type        = string
  # Example: "123456789012.collect.observeinc.com"
}
