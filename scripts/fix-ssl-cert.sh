#!/bin/bash
#
# Fix SSL certificate trust issue in Java service container
#
# This script:
# 1. Extracts the nginx self-signed certificate
# 2. Imports it into the Java truststore inside the java7-service container
# 3. Restarts the Java service
#

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get nginx IP from Terraform output
NGINX_IP=$(cd "$SCRIPT_DIR/../infra/terraform" && terraform output -raw nginx_proxy_public_ip)
NGINX_PRIVATE_IP=$(cd "$SCRIPT_DIR/../infra/terraform" && terraform output -raw nginx_proxy_private_ip)

echo "Nginx public IP: $NGINX_IP"
echo "Nginx private IP: $NGINX_PRIVATE_IP"

# Get the SSH key path
SSH_KEY="$HOME/.ssh/newrelic-observe-proxy-key.pem"

if [ ! -f "$SSH_KEY" ]; then
    echo "Error: SSH key not found at $SSH_KEY"
    exit 1
fi

echo ""
echo "Step 1: Extracting nginx certificate..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@$NGINX_IP \
    'sudo docker exec newrelic-proxy cat /etc/nginx/ssl/cert.pem' > /tmp/nginx.crt

if [ ! -s /tmp/nginx.crt ]; then
    echo "Error: Failed to extract certificate"
    exit 1
fi

echo "Certificate extracted to /tmp/nginx.crt"
echo ""

# Show certificate details
echo "Certificate details:"
openssl x509 -in /tmp/nginx.crt -noout -subject -issuer -dates
echo ""

# Get Java service IP
JAVA_IP=$(cd "$SCRIPT_DIR/../infra/terraform" && terraform output -raw java_service_public_ip)
echo "Java service IP: $JAVA_IP"
echo ""

echo "Step 2: Copying certificate to Java service container..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@$JAVA_IP \
    'cat > /tmp/nginx.crt' < /tmp/nginx.crt

echo "Step 3: Importing certificate into Java truststore..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@$JAVA_IP <<'ENDSSH'
# Copy cert into container
sudo docker cp /tmp/nginx.crt java7-service:/tmp/nginx.crt

# Import into Java truststore (password: changeit)
sudo docker exec java7-service keytool -import -trustcacerts -noprompt \
    -alias nginx-proxy \
    -file /tmp/nginx.crt \
    -keystore /usr/lib/jvm/java-1.8.0-amazon-corretto/jre/lib/security/cacerts \
    -storepass changeit

# Verify it was imported
echo "Verifying certificate import..."
sudo docker exec java7-service keytool -list -alias nginx-proxy \
    -keystore /usr/lib/jvm/java-1.8.0-amazon-corretto/jre/lib/security/cacerts \
    -storepass changeit
ENDSSH

echo ""
echo "Step 4: Restarting Java service..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@$JAVA_IP \
    'sudo docker restart java7-service'

echo ""
echo "Waiting 15 seconds for service to start..."
sleep 15

echo ""
echo "Step 5: Checking NewRelic agent logs..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@$JAVA_IP \
    'sudo docker logs --tail 20 java7-service 2>&1 | grep -E "(newrelic|SSL|connect)"'

echo ""
echo "==================================================================="
echo "SSL certificate fix applied!"
echo "==================================================================="
echo ""
echo "Next steps:"
echo "1. Generate traffic: curl http://$JAVA_IP:8080/"
echo "2. Check agent logs: ssh -i $SSH_KEY ec2-user@$JAVA_IP 'sudo docker logs java7-service'"
echo "3. Check nginx logs: ssh -i $SSH_KEY ec2-user@$NGINX_IP 'sudo docker exec nginx-proxy cat /var/log/nginx/newrelic-spans.jsonl'"
echo ""
