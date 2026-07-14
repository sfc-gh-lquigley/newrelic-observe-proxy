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

# Data source for latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security group for nginx proxy
resource "aws_security_group" "nginx_proxy" {
  name        = "newrelic-nginx-proxy-sg"
  description = "Security group for NewRelic nginx proxy"

  # HTTPS from Java service
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS for NewRelic agents"
  }

  # SSH for management
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "SSH access"
  }

  # Outbound to internet (for Observe)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name    = "newrelic-nginx-proxy-sg"
    Project = "newrelic-observe-proxy"
  }
}

# Security group for Java 7 service
resource "aws_security_group" "java_service" {
  name        = "newrelic-java-service-sg"
  description = "Security group for Java 7 test service"

  # HTTP for testing
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP for test traffic"
  }

  # SSH for management
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "SSH access"
  }

  # Outbound to nginx proxy
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name    = "newrelic-java-service-sg"
    Project = "newrelic-observe-proxy"
  }
}

# EC2 instance for nginx proxy
resource "aws_instance" "nginx_proxy" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = var.nginx_instance_type
  key_name      = var.key_pair_name

  vpc_security_group_ids = [aws_security_group.nginx_proxy.id]

  user_data = templatefile("${path.module}/../user-data/nginx-proxy.sh", {
    observe_token         = var.observe_token
    observe_endpoint_host = var.observe_endpoint_host
  })

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name    = "newrelic-nginx-proxy"
    Project = "newrelic-observe-proxy"
  }
}

# EC2 instance for Java 7 service
resource "aws_instance" "java_service" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = var.java_instance_type
  key_name      = var.key_pair_name

  vpc_security_group_ids = [aws_security_group.java_service.id]

  user_data = templatefile("${path.module}/../user-data/java-service.sh", {
    nginx_host = aws_instance.nginx_proxy.private_ip
  })

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name    = "newrelic-java-service"
    Project = "newrelic-observe-proxy"
  }

  depends_on = [aws_instance.nginx_proxy]
}

# Elastic IPs for stable addressing
resource "aws_eip" "nginx_proxy" {
  instance = aws_instance.nginx_proxy.id
  domain   = "vpc"

  tags = {
    Name    = "newrelic-nginx-proxy-eip"
    Project = "newrelic-observe-proxy"
  }
}

resource "aws_eip" "java_service" {
  instance = aws_instance.java_service.id
  domain   = "vpc"

  tags = {
    Name    = "newrelic-java-service-eip"
    Project = "newrelic-observe-proxy"
  }
}
