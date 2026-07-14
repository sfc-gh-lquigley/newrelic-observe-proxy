# Validation Scripts

Scripts to test the end-to-end flow of NewRelic spans → nginx → Observe.

## Scripts

### 1. generate-load.sh

Generates HTTP traffic to the Java 7 test service, which creates NewRelic spans.

**Usage:**
```bash
./generate-load.sh <java-service-url> [duration-seconds] [requests-per-second]
```

**Examples:**
```bash
# Default: 60 seconds, 10 req/s
./generate-load.sh http://54.123.45.67:8080

# Custom: 120 seconds, 20 req/s
./generate-load.sh http://54.123.45.67:8080 120 20

# Quick test: 10 seconds, 5 req/s
./generate-load.sh http://54.123.45.67:8080 10 5
```

**What it does:**
- Calls `/api/users` and `/api/orders/{userId}` endpoints randomly
- Each request generates 2-3 spans (servlet + database queries)
- Reports success rate and actual RPS

### 2. check-nginx-logs.sh

Connects to the nginx proxy via SSH and analyzes captured spans.

**Usage:**
```bash
./check-nginx-logs.sh <nginx-ip> [ssh-key-path]
```

**Examples:**
```bash
# Using default SSH key (~/.ssh/id_rsa)
./check-nginx-logs.sh 54.123.45.67

# Using specific key
./check-nginx-logs.sh 54.123.45.67 ~/.ssh/my-aws-key.pem
```

**What it does:**
- Verifies nginx container is running
- Counts captured span events
- Shows sample payloads
- Analyzes NewRelic method types
- Reports any nginx errors

## Complete Testing Flow

### 1. Deploy Infrastructure

```bash
cd infra/terraform
terraform apply
```

Note the output IPs.

### 2. Wait for Setup

User data scripts take ~5 minutes to complete:
- Install Docker
- Clone repo
- Build containers
- Start services

Verify readiness:
```bash
# Check nginx
curl -k https://<nginx-ip>:443/health

# Check Java service
curl http://<java-service-ip>:8080/api/users
```

### 3. Generate Load

```bash
cd validation
./generate-load.sh http://<java-service-ip>:8080 60 10
```

This sends 600 requests over 60 seconds, generating ~1200-1800 spans.

### 4. Verify Spans in Nginx

```bash
./check-nginx-logs.sh <nginx-ip> ~/.ssh/your-key.pem
```

Expected output:
```
✓ Nginx container running
✓ Captured 1500 span events
✓ No errors detected
```

### 5. Check Observe

Log in to Observe UI and query the HTTP ingest datastream:

```sql
-- View raw NewRelic events
from datastream("your-datastream-id")
limit 100
```

You should see JSON payloads with this structure:
```json
[
  "license_key",
  {"reservoir_size": 10000, "events_seen": 1},
  [
    [
      {"type": "Span", "traceId": "...", "name": "WebTransaction/Servlet/UsersServlet"},
      {},
      {"http.method": "GET", "http.url": "..."}
    ]
  ]
]
```

### 6. Flatten Data with OPAL

Create OPAL queries to extract span fields:

```sql
from datastream("your-datastream-id")
// Flatten the span array (payload[2])
flatten(body[2]) as span_event
// Extract intrinsic attributes (first element)
make_col trace_id: span_event[0].traceId
make_col span_id: span_event[0].guid
make_col span_name: span_event[0].name
make_col duration: span_event[0].duration
make_col timestamp: span_event[0].timestamp
// Extract custom attributes (third element)
make_col http_method: span_event[2]["http.method"]
make_col http_url: span_event[2]["http.url"]
make_col http_status: span_event[2]["http.statusCode"]
```

### 7. Document Results

Update `docs/findings.md` with:
- Actual NewRelic JSON payload structure
- Span counts and types
- Any issues encountered
- OPAL query examples
- Recommendations for production

## Troubleshooting

### No spans captured

**Symptoms:**
```
⚠ No spans captured yet!
```

**Check:**
1. Java service is running: `ssh ec2-user@<java-ip> 'docker ps'`
2. NewRelic agent logs: `ssh ec2-user@<java-ip> 'docker logs java7-service | grep -i newrelic'`
3. Agent configuration: `ssh ec2-user@<java-ip> 'docker exec java7-service cat /app/newrelic/newrelic.yml'`
4. Network connectivity: `ssh ec2-user@<java-ip> 'curl -k https://<nginx-ip>:443/health'`

### Low span count

If you generated 600 requests but only see 50 spans:
- Agent batches spans (may not flush immediately)
- Check agent buffer settings in newrelic.yml
- Wait a few minutes for agent to flush

### Nginx errors

If `check-nginx-logs.sh` reports errors:
```bash
ssh -i ~/.ssh/key.pem ec2-user@<nginx-ip>
docker logs newrelic-proxy
sudo tail -f /var/log/nginx/error.log
```

Common issues:
- Observe token invalid → Check `OBSERVE_TOKEN` environment variable
- Observe endpoint unreachable → Verify `OBSERVE_ENDPOINT_HOST`
- SSL errors → Check nginx certificate

## Manual Testing

### Watch spans in real-time

```bash
ssh -i ~/.ssh/key.pem ec2-user@<nginx-ip>
sudo tail -f /var/log/nginx/newrelic-spans.jsonl | jq .
```

### Extract span data

```bash
ssh -i ~/.ssh/key.pem ec2-user@<nginx-ip>

# Count total spans
sudo cat /var/log/nginx/newrelic-spans.jsonl | wc -l

# Extract unique trace IDs
sudo cat /var/log/nginx/newrelic-spans.jsonl | \
  jq -r '.request_body | fromjson | .[2] | .[] | .[0].traceId' | \
  sort -u | wc -l

# Show span names
sudo cat /var/log/nginx/newrelic-spans.jsonl | \
  jq -r '.request_body | fromjson | .[2] | .[] | .[0].name' | \
  sort | uniq -c
```

## Performance Testing

### High-volume test

```bash
# 10 minutes at 100 req/s = 60,000 requests
./generate-load.sh http://<java-service-ip>:8080 600 100
```

Then check:
1. Nginx CPU/memory: `ssh ec2-user@<nginx-ip> 'docker stats newrelic-proxy'`
2. Span drop rate: Compare requests sent vs spans captured
3. Observe ingest lag: Check timestamps in Observe vs nginx logs

## Success Criteria

A successful validation should show:
- ✅ Java service responds to HTTP requests
- ✅ NewRelic agent connects to nginx (check agent logs)
- ✅ Nginx captures spans (check nginx logs)
- ✅ Spans forwarded to Observe (check Observe UI)
- ✅ OPAL queries successfully flatten data
- ✅ No dropped spans under normal load
- ✅ Reasonable latency (< 100ms overhead)
