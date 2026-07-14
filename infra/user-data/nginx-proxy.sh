#!/bin/bash
#
# User data script for nginx proxy EC2 instance
#

set -e

# Update system
yum update -y

# Install Docker
amazon-linux-extras install docker -y
systemctl start docker
systemctl enable docker

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install git
yum install -y git

# Clone repository
cd /home/ec2-user
git clone https://github.com/sfc-gh-lquigley/newrelic-observe-proxy.git
cd newrelic-observe-proxy/nginx-proxy

# Generate self-signed SSL certificate
./generate-cert.sh

# Build and run nginx container
docker build -t newrelic-nginx-proxy .

docker run -d \
  --name newrelic-proxy \
  --restart unless-stopped \
  -p 443:443 \
  -e OBSERVE_TOKEN="${observe_token}" \
  -e OBSERVE_ENDPOINT_HOST="${observe_endpoint_host}" \
  -v /var/log/nginx:/var/log/nginx \
  newrelic-nginx-proxy

# Wait for nginx to start
sleep 5

# Verify nginx is running
docker ps | grep newrelic-proxy

# Log completion
echo "Nginx proxy setup complete!" > /home/ec2-user/setup-complete.txt
echo "View logs: docker logs newrelic-proxy" >> /home/ec2-user/setup-complete.txt
echo "View spans: tail -f /var/log/nginx/newrelic-spans.jsonl" >> /home/ec2-user/setup-complete.txt
