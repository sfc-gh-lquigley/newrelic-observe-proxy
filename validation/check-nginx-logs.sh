#!/bin/bash
#
# Check nginx logs for captured NewRelic spans
# Usage: ./check-nginx-logs.sh <nginx-ip> [ssh-key]
#

set -e

NGINX_IP="$1"
SSH_KEY="${2:-$HOME/.ssh/id_rsa}"

if [ -z "$NGINX_IP" ] || [ "$NGINX_IP" = "-h" ] || [ "$NGINX_IP" = "--help" ]; then
    echo "Usage: $0 <nginx-ip> [ssh-key-path]"
    echo ""
    echo "Examples:"
    echo "  $0 54.123.45.67"
    echo "  $0 54.123.45.67 ~/.ssh/my-key.pem"
    echo ""
    exit 1
fi

echo "========================================="
echo "NewRelic Observe Proxy - Log Checker"
echo "========================================="
echo "Nginx IP: $NGINX_IP"
echo "SSH Key: $SSH_KEY"
echo "========================================="
echo ""

# Check if we can SSH
echo "Testing SSH connection..."
if ! ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ec2-user@"$NGINX_IP" "echo 'Connected'" 2>/dev/null; then
    echo "ERROR: Cannot SSH to $NGINX_IP"
    echo "- Verify IP address is correct"
    echo "- Check security group allows SSH from your IP"
    echo "- Confirm SSH key path is correct"
    exit 1
fi

echo "✓ SSH connection successful"
echo ""

# Check if Docker container is running
echo "Checking nginx container status..."
CONTAINER_STATUS=$(ssh -i "$SSH_KEY" ec2-user@"$NGINX_IP" "docker ps --filter name=newrelic-proxy --format '{{.Status}}'" 2>/dev/null)

if [ -z "$CONTAINER_STATUS" ]; then
    echo "✗ Nginx container is not running!"
    echo ""
    echo "Checking Docker logs..."
    ssh -i "$SSH_KEY" ec2-user@"$NGINX_IP" "docker logs newrelic-proxy 2>&1 | tail -20"
    exit 1
fi

echo "✓ Nginx container running: $CONTAINER_STATUS"
echo ""

# Count captured spans
echo "Analyzing NewRelic span logs..."
SPAN_COUNT=$(ssh -i "$SSH_KEY" ec2-user@"$NGINX_IP" "sudo wc -l /var/log/nginx/newrelic-spans.jsonl 2>/dev/null | awk '{print \$1}'" || echo "0")

echo "Total log entries: $SPAN_COUNT"
echo ""

if [ "$SPAN_COUNT" -eq 0 ]; then
    echo "⚠ No spans captured yet!"
    echo ""
    echo "Possible reasons:"
    echo "1. Java service hasn't sent data yet"
    echo "2. NewRelic agent not configured correctly"
    echo "3. Network connectivity issues"
    echo ""
    echo "Troubleshooting:"
    echo "- Check Java service logs: ssh ec2-user@<java-ip> 'docker logs java7-service'"
    echo "- Verify agent config: ssh ec2-user@<java-ip> 'docker exec java7-service cat /app/newrelic/newrelic.yml'"
    echo "- Test nginx endpoint: curl -k https://$NGINX_IP:443/health"
    exit 1
fi

# Show sample spans
echo "Sample spans (last 5 entries):"
echo "---"
ssh -i "$SSH_KEY" ec2-user@"$NGINX_IP" "sudo tail -5 /var/log/nginx/newrelic-spans.jsonl | jq -r '.request_body' 2>/dev/null || sudo tail -5 /var/log/nginx/newrelic-spans.jsonl"
echo "---"
echo ""

# Check for specific NewRelic methods
echo "NewRelic method breakdown:"
METHODS=$(ssh -i "$SSH_KEY" ec2-user@"$NGINX_IP" "sudo cat /var/log/nginx/newrelic-spans.jsonl | grep -o 'method=[^&]*' | sort | uniq -c" 2>/dev/null || echo "Unable to parse methods")
echo "$METHODS"
echo ""

# Check nginx error log
echo "Recent nginx errors (if any):"
ERROR_COUNT=$(ssh -i "$SSH_KEY" ec2-user@"$NGINX_IP" "sudo wc -l /var/log/nginx/error.log 2>/dev/null | awk '{print \$1}'" || echo "0")

if [ "$ERROR_COUNT" -gt 0 ]; then
    echo "✗ Found $ERROR_COUNT error log entries:"
    ssh -i "$SSH_KEY" ec2-user@"$NGINX_IP" "sudo tail -10 /var/log/nginx/error.log"
else
    echo "✓ No errors logged"
fi

echo ""
echo "========================================="
echo "Summary"
echo "========================================="
echo "✓ Nginx proxy is running"
echo "✓ Captured $SPAN_COUNT span events"
if [ "$ERROR_COUNT" -eq 0 ]; then
    echo "✓ No errors detected"
else
    echo "⚠ $ERROR_COUNT errors logged"
fi
echo ""
echo "Next steps:"
echo "1. Verify data in Observe UI"
echo "2. Test OPAL queries for data flattening"
echo "3. Document findings in docs/findings.md"
echo ""
echo "Useful commands:"
echo "  # Watch live spans"
echo "  ssh -i $SSH_KEY ec2-user@$NGINX_IP 'sudo tail -f /var/log/nginx/newrelic-spans.jsonl'"
echo ""
echo "  # View full nginx logs"
echo "  ssh -i $SSH_KEY ec2-user@$NGINX_IP 'docker logs -f newrelic-proxy'"
