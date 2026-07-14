# Nginx Proxy for NewRelic Agent

Nginx proxy that intercepts NewRelic agent traffic and forwards it to Observe HTTP ingest.

## What It Does

1. **Listens on port 443** (HTTPS) for NewRelic agent connections
2. **Mocks NewRelic collector** responses to keep agents happy
3. **Logs raw payloads** to `/var/log/nginx/newrelic-spans.jsonl`
4. **Forwards to Observe** HTTP ingest endpoint

## Configuration

The proxy is configured via environment variables:

- `OBSERVE_TOKEN` - Observe datastream token (required)
- `OBSERVE_ENDPOINT_HOST` - Observe ingest hostname without protocol (e.g., `123456789012.collect.observeinc.com`)

## SSL Certificates

Generate self-signed certificates for testing:

```bash
./generate-cert.sh
```

This creates `ssl/cert.pem` and `ssl/key.pem`.

## Running Locally

### Prerequisites
- Docker installed
- SSL certificates generated
- Observe credentials

### Start
```bash
docker build -t newrelic-nginx-proxy .

docker run -d \
  -p 443:443 \
  -e OBSERVE_TOKEN="your-datastream-token" \
  -e OBSERVE_ENDPOINT_HOST="123456789012.collect.observeinc.com" \
  --name nr-proxy \
  newrelic-nginx-proxy
```

### Verify
```bash
# Health check
curl -k https://localhost:443/health

# Check logs
docker logs nr-proxy

# View captured spans
docker exec nr-proxy tail -f /var/log/nginx/newrelic-spans.jsonl
```

## Testing with NewRelic Agent

Configure a NewRelic agent to point to this proxy:

```yaml
# newrelic.yml
common:
  host: 'localhost'  # or nginx container IP
  port: 443
  ssl: true
```

When the agent sends spans, you should see:
1. Logs in `/var/log/nginx/newrelic-spans.jsonl`
2. Data forwarded to Observe

## NewRelic Agent Handshake

The proxy handles the NewRelic agent connection protocol:

### Step 1: Connect
```
GET /agent_listener/invoke_raw_method?method=connect&...
```

**Proxy Response:**
```json
{
  "return_value": {
    "agent_run_id": "mock-run-id-12345",
    "messages": []
  }
}
```

### Step 2: Send Data
```
POST /agent_listener/invoke_raw_method?method=analytic_event_data&...
```

**Proxy Actions:**
1. Logs the request body
2. Forwards to Observe
3. Returns success to agent

```json
{
  "return_value": null
}
```

## Nginx Configuration Details

Key configuration sections in `nginx.conf`:

### Request Logging
```nginx
log_format newrelic_spans escape=json
    '{'
    '"timestamp":"$time_iso8601",'
    '"request_body":"$request_body"'
    '}';
```

### Observe Forwarding
```nginx
location /agent_listener/invoke_raw_method {
    proxy_pass https://observe;
    proxy_set_header Authorization "Bearer ${OBSERVE_TOKEN}";
    return 200 '{"return_value": null}';
}
```

### Error Handling
Even if Observe is down, the proxy returns success to the agent to prevent retry storms.

## Monitoring

### Check nginx is running
```bash
docker ps | grep nr-proxy
```

### View logs
```bash
# Nginx error log
docker exec nr-proxy tail -f /var/log/nginx/error.log

# NewRelic payloads
docker exec nr-proxy tail -f /var/log/nginx/newrelic-spans.jsonl
```

### Test health endpoint
```bash
curl -k https://localhost:443/health
```

## Troubleshooting

### Agent can't connect
- Verify nginx is listening: `docker ps`
- Check SSL certificate is valid
- Test with curl: `curl -k https://localhost:443/`

### No spans in logs
- Check agent is configured correctly
- Verify agent is generating traffic
- Look for errors in nginx error log

### Observe not receiving data
- Verify `OBSERVE_TOKEN` is correct
- Check `OBSERVE_ENDPOINT_HOST` is correct hostname
- Test Observe endpoint manually with curl

## Production Deployment

For production use:

1. **Use proper SSL certificates** (Let's Encrypt or CA-signed)
2. **Deploy 2+ instances** for high availability
3. **Add load balancer** in front of nginx instances
4. **Enable SSL verification** (`proxy_ssl_verify on`)
5. **Monitor nginx health** (CloudWatch, Datadog, etc.)
6. **Set up alerts** (nginx down, high error rate)
