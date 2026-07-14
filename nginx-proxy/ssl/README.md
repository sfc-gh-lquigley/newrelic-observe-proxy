# SSL Certificates

This directory contains SSL certificates for the nginx proxy.

## Generating Self-Signed Certificates

For testing, generate a self-signed certificate:

```bash
cd nginx-proxy
./generate-cert.sh
```

This creates:
- `ssl/cert.pem` - Public certificate
- `ssl/key.pem` - Private key

## Using with Java 7

Java 7's default truststore may not trust self-signed certificates. To add the certificate to Java's truststore:

```bash
# Export certificate to Java's cacerts
keytool -import -alias newrelic-proxy \
    -file ssl/cert.pem \
    -keystore $JAVA_HOME/jre/lib/security/cacerts \
    -storepass changeit
```

## Production Certificates

For production use, obtain a proper CA-signed certificate from:
- Let's Encrypt (free)
- Your organization's certificate authority
- Commercial CA (DigiCert, etc.)

Place the certificate and key in this directory as:
- `cert.pem`
- `key.pem`
