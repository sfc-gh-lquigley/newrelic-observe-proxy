#!/bin/bash
#
# User data script for Java 7 service EC2 instance
#

set -e

# Update system
yum update -y

# Install Docker
amazon-linux-extras install docker -y
systemctl start docker
systemctl enable docker

# Install git
yum install -y git wget unzip

# Clone repository
cd /home/ec2-user
git clone https://github.com/sfc-gh-lquigley/newrelic-observe-proxy.git
cd newrelic-observe-proxy/java-service

# Download NewRelic Java Agent v6.5.0
echo "Downloading NewRelic Java Agent v6.5.0..."
wget -q https://download.newrelic.com/newrelic/java-agent/newrelic-agent/6.5.0/newrelic-java-6.5.0.zip
unzip -o -q newrelic-java-6.5.0.zip
cp newrelic/newrelic.jar newrelic/
rm -rf newrelic-java-6.5.0.zip newrelic/

# Build Docker image
docker build -t java7-test-service .

# Run Java service with NewRelic agent pointing to nginx
docker run -d \
  --name java7-service \
  --restart unless-stopped \
  -p 8080:8080 \
  -e NGINX_HOST="${nginx_host}" \
  java7-test-service

# Wait for service to start
sleep 10

# Verify service is running
docker ps | grep java7-service

# Test endpoints
curl -f http://localhost:8080/api/users || echo "Service not ready yet"

# Log completion
echo "Java 7 service setup complete!" > /home/ec2-user/setup-complete.txt
echo "NewRelic agent configured to: ${nginx_host}:443" >> /home/ec2-user/setup-complete.txt
echo "Test API: curl http://localhost:8080/api/users" >> /home/ec2-user/setup-complete.txt
echo "View logs: docker logs java7-service" >> /home/ec2-user/setup-complete.txt
