#!/bin/bash
#
# Generate self-signed SSL certificate for nginx with SAN for IP addresses
#
# Usage: ./generate-cert.sh [nginx-private-ip]
# Example: ./generate-cert.sh 172.31.39.62

set -e

NGINX_IP="${1:-172.31.39.62}"  # Default to common private IP or use passed value

echo "Generating self-signed SSL certificate for NewRelic proxy..."
echo "Including SAN for IP: $NGINX_IP"

# Create OpenSSL config with SAN
cat > /tmp/openssl-san.cnf << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[dn]
C=US
ST=State
L=City
O=Organization
CN=collector.newrelic.com

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = collector.newrelic.com
DNS.2 = localhost
IP.1 = $NGINX_IP
IP.2 = 127.0.0.1
EOF

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout ssl/key.pem \
    -out ssl/cert.pem \
    -config /tmp/openssl-san.cnf \
    -extensions req_ext

rm /tmp/openssl-san.cnf

echo ""
echo "Certificate generated:"
echo "  - ssl/cert.pem"
echo "  - ssl/key.pem"
echo ""
echo "Subject Alternative Names:"
echo "  - DNS: collector.newrelic.com"
echo "  - DNS: localhost"
echo "  - IP: $NGINX_IP"
echo "  - IP: 127.0.0.1"
echo ""
echo "Note: This is a self-signed certificate for testing only."
echo "For production, use a proper CA-signed certificate."
