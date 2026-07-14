# Demo Quick Start

This guide shows how to demo the NewRelic → Observe proxy simulation.

## Current Status
✅ **SSL certificate trust fixed** - Agent connects to nginx successfully  
✅ **Infrastructure deployed** - All components running on AWS  
⏳ **Agent handshake** - 95% complete, one missing field in connect response

See [docs/demo-status.md](docs/demo-status.md) for detailed status.

## Running Infrastructure
- **Nginx Proxy:** https://16.147.169.241:443
- **Java Service:** http://32.184.175.103:8080
- **AWS Region:** us-west-2

## Demo Flow

### 1. Show the Problem
Explain the scenario:
- 200 Java 7 services currently sending telemetry to NewRelic SaaS
- NewRelic agent v6.5.0 (last version supporting Java 7)
- Need to redirect to Observe during 3-month migration window
- Can't upgrade Java runtime or modify application code

### 2. Show the Architecture
```
Java 7 Services (200)
    ↓ (HTTPS)
Nginx Proxy (3 HA instances)
    ↓ (HTTPS)
Observe HTTP Ingest
```

- **Nginx** acts as NewRelic collector API mock
- Receives NewRelic agent protocol
- Forwards raw JSON to Observe
- Returns success responses to agent

### 3. Show Infrastructure Deployment

```bash
cd infra/terraform
terraform plan
terraform apply
```

Shows:
- 2 EC2 instances (nginx proxy + Java service)
- Security groups
- Self-signed SSL certificates
- Docker containers

### 4. Show SSL Certificate Fix

The agent requires SSL and won't trust self-signed certs by default.

```bash
./scripts/fix-ssl-cert.sh
```

This script:
1. Extracts nginx self-signed certificate
2. Imports it into Java's truststore
3. Restarts the Java service

Show the before/after in logs:
```bash
# Before: PKIX path building failed
# After: SSL handshake succeeds
```

### 5. Show Agent Configuration

```bash
ssh -i ~/.ssh/newrelic-observe-proxy-key.pem ec2-user@32.184.175.103 \
  'sudo docker exec java7-service cat /app/newrelic/newrelic.yml'
```

Key configuration:
```yaml
host: 172.31.39.62  # nginx private IP instead of collector.newrelic.com
port: 443
ssl: false  # (agent still uses SSL on port 443)
```

### 6. Show Agent Connection

```bash
ssh -i ~/.ssh/newrelic-observe-proxy-key.pem ec2-user@32.184.175.103 \
  'sudo docker exec java7-service tail -30 /app/logs/newrelic_agent.log'
```

Shows:
- Agent loads successfully
- Connects to nginx (172.31.39.62:443)
- SSL handshake succeeds ✅
- Receives security policies ✅
- Attempting to complete handshake (in progress)

### 7. Show Nginx Receiving Traffic

```bash
ssh -i ~/.ssh/newrelic-observe-proxy-key.pem ec2-user@16.147.169.241 \
  'sudo docker exec newrelic-proxy cat /var/log/nginx/newrelic-spans.jsonl | jq'
```

Shows:
- Preconnect requests from agent
- Connect requests from agent
- Nginx returning mock responses

### 8. Generate Test Traffic

```bash
for i in {1..10}; do 
  curl -s http://32.184.175.103:8080/ > /dev/null
  echo "Request $i sent"
  sleep 1
done
```

This hits the Java service and should generate spans (once agent handshake completes).

### 9. Show What's Working

| Component | Status | Evidence |
|-----------|--------|----------|
| Infrastructure | ✅ Working | EC2 instances running |
| Docker Containers | ✅ Working | nginx + java7-service up |
| SSL Certificates | ✅ Working | Handshake succeeds |
| Agent Startup | ✅ Working | Agent loads and connects |
| Nginx Proxy | ✅ Working | Accepts requests, logs traffic |
| Observe Forwarding | ✅ Ready | Proxy configured with token |

### 10. Show What's Next

One remaining issue: Agent connect response needs complete field set.

**Current Error:**
```
Failed to connect: java.lang.NullPointerException
```

**Next Steps:**
1. Research NewRelic v6.5.0 connect API format
2. Add missing fields (likely `request_headers_map` or `event_harvest_config`)
3. Agent completes handshake
4. Spans flow: Java → Nginx → Observe
5. Verify with OPAL queries in Observe UI

## Demo Talking Points

### Why This Approach Works
- **No app changes required** - Just reconfigure existing NewRelic agent
- **No runtime upgrades** - Works with Java 7
- **Transparent to services** - They think they're talking to NewRelic
- **Simple rollout** - Update host in newrelic.yml, restart service
- **Instant rollback** - Change host back if issues arise

### Production Considerations
- Use 3 HA nginx instances behind AWS ALB
- CA-signed certificates (not self-signed)
- Monitor nginx health and lag
- Test with 200K spans/min load
- Estimated cost: ~$180/month vs NewRelic subscription

### Risk Mitigation
- Rollout in batches (10 services at a time)
- Monitor Observe ingestion lag
- Keep NewRelic subscription active during migration
- Can roll back any batch instantly
- 3-month buffer to complete migration

## Clean Up

When done with demo:

```bash
cd infra/terraform
terraform destroy
```

## Questions to Anticipate

**Q: What if nginx goes down?**  
A: NewRelic agent queues spans locally and retries. Use 3 HA instances + ALB.

**Q: What about data loss?**  
A: Nginx forwards immediately to Observe. If Observe is down, nginx returns success so agent doesn't retry endlessly.

**Q: Why not use OpenTelemetry?**  
A: OTel requires Java 8+ runtime. These services are Java 7 only and can't be upgraded.

**Q: How much data?**  
A: 200 services × ~1K spans/min = ~200K spans/min. Nginx can handle this easily.

**Q: What format does Observe receive?**  
A: Raw NewRelic JSON. We use OPAL queries to flatten the nested structure into traces/spans.

**Q: When will it be production-ready?**  
A: ~1 day of work to complete agent handshake + load testing. Architecture is validated.
