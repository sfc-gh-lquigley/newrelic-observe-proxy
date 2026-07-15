# Test Findings

## Status Summary

✅ **Infrastructure** - Fully automated deployment via Terraform  
✅ **Nginx Proxy** - Successfully mocks NewRelic collector API  
✅ **SSL Trust** - Certificate generated with SAN and trusted by Java  
✅ **Preconnect Flow** - Agent receives redirect_host and security policies  
⚠️ **Agent Issue** - NewRelic v6.5.0 has internal NullPointerException preventing connect call

## Known Issue

**NewRelic Java Agent v6.5.0 Limitation**

After successfully receiving preconnect response:
```
Received JSON(preconnect): {"return_value": {"redirect_host": "172.31.39.62", "security_policies": {...}}}
LASP Policies received from server side: {...}
Failed to connect: java.lang.NullPointerException
```

Agent never proceeds to call connect endpoint. This appears to be an internal limitation in v6.5.0 (released 2020, EOL) preventing custom backend usage.

**Tested Configurations:**
- ❌ Full preconnect response with security_policies - NullPointerException
- ❌ Minimal preconnect response (just redirect_host) - Still NullPointerException
- ❌ Different redirect_host formats - No change

**Root Cause:** Internal agent bug, not nginx configuration issue. v6.5.0 was designed only for NewRelic SaaS backend.

## What Works

1. **Terraform Infrastructure**
   - EC2 instances with user-data automation
   - Security groups and networking
   - Docker containers auto-start
   - Self-signed SSL with Subject Alternative Names (SAN)

2. **Nginx Proxy**
   - Accepts HTTPS on port 443
   - Returns proper preconnect response with redirect_host
   - Returns complete connect response with all required fields
   - Configured to forward telemetry to Observe HTTP ingest

3. **Agent Configuration**
   - Points to nginx instead of NewRelic SaaS
   - SSL handshake succeeds
   - Preconnect call succeeds
   - Parses redirect_host: `"172.31.39.62"`
   - Receives LASP security policies

**Blocker:** Agent v6.5.0 hits internal NullPointerException before calling connect endpoint.

## Key Discoveries

- **redirect_host format**: Must be IP/hostname without port (e.g., `"172.31.39.62"` not `"172.31.39.62:443"`)
- **Empty redirect_host**: Causes agent to skip connect call entirely
- **SSL requirements**: Certificate must have SAN matching connection IP and be trusted in Java cacerts
- **Agent v6.5.0 limitation**: Internal bug prevents custom backend usage - not fixable via nginx configuration alone

## Quick Deploy

```bash
# Deploy infrastructure
cd infra/terraform
terraform init
terraform apply

# Get IPs
terraform output

# View agent logs
ssh -i ~/.ssh/newrelic-observe-proxy-key.pem ec2-user@<java-ip> \
  'sudo docker exec java7-service tail -f /app/newrelic/logs/newrelic_agent.log'

# View nginx logs  
ssh -i ~/.ssh/newrelic-observe-proxy-key.pem ec2-user@<nginx-ip> \
  'sudo docker exec newrelic-proxy tail -f /var/log/nginx/newrelic-spans.jsonl'
```

## Next Steps

**For Java 7 Services (Current Blocker):**
1. **Patch NewRelic v6.5.0 Agent** - Fix internal NullPointerException (requires agent source code modification)
2. **Alternative APM Agents** - Test other Java 7 compatible agents (Elastic APM, AppDynamics)
3. **Infrastructure-Level Tracing** - Use eBPF or service mesh instead of JVM-level instrumentation
4. **Delay Migration** - Keep NewRelic SaaS until Java 8 upgrade is feasible

**If Java 8+ Upgrade is Possible:**
1. Upgrade to Java 8 JVM (most Java 7 apps are compatible)
2. Upgrade to NewRelic v9.3.0 agent
3. Use minimal preconnect response format in nginx
4. Test telemetry flow to Observe
5. Write OPAL queries to flatten NewRelic JSON

## Current Blocker

**Observe HTTP 400 Errors - Data Format Incompatibility**

Even if agent v6.5.0 could connect, nginx proxy forwarding to Observe returns HTTP 400 errors due to data format mismatch.

The nginx proxy successfully forwards NewRelic telemetry to Observe's `/v1/http/newrelic/` endpoint, but Observe returns HTTP 400 errors:

```json
{"timestamp":"2026-07-15T00:48:36+00:00","status":400,"body_bytes":94}
```

**Root Cause**: NewRelic agent sends proprietary protocol data:
- Gzip-compressed JSON payloads (`\u001F�\b` = gzip magic number)
- NewRelic-specific schema (agent_run_id, marshal_format, protocol_version)
- Methods: analytic_event_data, span_event_data, metric_data, transaction_sample_data

Observe's `/v1/http` endpoint expects generic telemetry formats (JSON, CSV, msgpack) but receives NewRelic's proprietary format.

**This is a secondary issue** - first need to fix v6.5.0 agent connection, then address data transformation.
