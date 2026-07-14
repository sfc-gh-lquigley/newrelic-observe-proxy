#!/bin/bash
#
# Generate self-signed SSL certificate for nginx
#

set -e

echo "Generating self-signed SSL certificate for NewRelic proxy..."

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout ssl/key.pem \
    -out ssl/cert.pem \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=collector.newrelic.com"

echo ""
echo "Certificate generated:"
echo "  - ssl/cert.pem"
echo "  - ssl/key.pem"
echo ""
echo "Note: This is a self-signed certificate for testing only."
echo "For production, use a proper CA-signed certificate."
