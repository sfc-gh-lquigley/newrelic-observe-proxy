FROM nginx:1.24-alpine

# Install envsubst for environment variable substitution
RUN apk add --no-cache gettext

# Copy nginx configuration template
COPY nginx.conf /etc/nginx/nginx.conf.template

# Copy SSL certificates
COPY ssl/cert.pem /etc/nginx/ssl/cert.pem
COPY ssl/key.pem /etc/nginx/ssl/key.pem

# Create log directory
RUN mkdir -p /var/log/nginx && \
    touch /var/log/nginx/newrelic-spans.jsonl && \
    chmod 666 /var/log/nginx/newrelic-spans.jsonl

# Expose HTTPS port
EXPOSE 443

# Start nginx with environment variable substitution
CMD ["/bin/sh", "-c", "envsubst '${OBSERVE_TOKEN} ${OBSERVE_ENDPOINT_HOST}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf && nginx -g 'daemon off;'"]
