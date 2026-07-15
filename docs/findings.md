# Test Findings

## Critical Discovery: Agent Version Matters

**Problem**: NewRelic Java Agent v6.5.0 (EOL 2020, last Java 7 compatible) has internal bugs preventing connection to custom backends.

**Solution**: Upgrade to NewRelic Java Agent v9.3.0 (latest 2024).

| Agent Version | Java Version | Custom Backend Support | Notes |
|---------------|--------------|------------------------|-------|
| **v6.5.0** | Java 7 | ❌ **Broken** | NullPointerException after preconnect; never calls connect endpoint |
| **v9.3.0** | Java 8+ | ✅ **Works** | Successfully connects and sends all telemetry with minimal preconnect response |

**Impact**: Original goal of using existing Java 7 services with v6.5.0 agent is not viable without patching the agent. Services must upgrade to Java 8+ to use v9.3.0.

## Status Summary

✅ **Infrastructure** - Fully automated deployment via Terraform  
✅ **Nginx Proxy** - Successfully mocks NewRelic collector API  
✅ **SSL Trust** - Certificate generated with SAN and trusted by Java  
✅ **Agent Connection** - NewRelic v9.3.0 successfully connects and sends telemetry  
✅ **Telemetry Flow** - Agent sending metrics, logs, events, and spans to nginx proxy  

## Solution

**Working Configuration: Agent v9.3.0 + Minimal Preconnect**

The NewRelic Java agent requires a minimal preconnect response format:
```json
{"return_value": {"redirect_host": "172.31.39.62"}}
```

**Key Findings:**
- Agent v6.5.0 (Java 7 compatible, EOL 2020) - ❌ Has NullPointerException with security_policies in preconnect
- Agent v9.3.0 (Latest, 2024, requires Java 8+) - ✅ Works perfectly with minimal response (CubeAPM style)
- Security policies in preconnect response cause both agents to fail initially
- Minimal response format (just redirect_host) allows v9.3.0 to succeed
- **v6.5.0 still fails even with minimal response** - internal agent bug, not fixable via nginx config

## What Works

1. **Terraform Infrastructure**
   - EC2 instances with user-data automation
   - Security groups and networking
   - Docker containers auto-start
   - Self-signed SSL with Subject Alternative Names (SAN)

2. **Nginx Proxy**
   - Accepts HTTPS on port 443
   - Returns minimal preconnect response: `{"return_value": {"redirect_host": "172.31.39.62"}}`
   - Returns complete connect response with agent_run_id and config
   - Forwards all telemetry to Observe HTTP ingest

3. **Agent v9.3.0 Telemetry**
   - Preconnect succeeds
   - Connect succeeds (gets mock-run-id-12345)
   - Sends analytic_event_data (transaction events)
   - Sends log_event_data (application logs)
   - Sends metric_data (performance metrics)
   - Sends update_loaded_modules (jar inventory)
   - Sends get_agent_commands (command polling)

## Evidence from Logs

**Agent Logs (00:38:06):**
```
Sent JSON(analytic_event_data) to: https://172.31.39.62:443/agent_listener/invoke_raw_method?method=analytic_event_data&...&run_id=mock-run-id-12345
Sent JSON(log_event_data) to: https://172.31.39.62:443/agent_listener/invoke_raw_method?method=log_event_data&...&run_id=mock-run-id-12345
Sent JSON(metric_data) to: https://172.31.39.62:443/agent_listener/invoke_raw_method?method=metric_data&...&run_id=mock-run-id-12345
```

**Nginx Logs:**
```json
{"timestamp":"2026-07-15T00:38:06+00:00","method":"POST","uri":"/agent_listener/invoke_raw_method?method=connect&...","status":200}
{"timestamp":"2026-07-15T00:38:06+00:00","method":"POST","uri":"/agent_listener/invoke_raw_method?method=analytic_event_data&...&run_id=mock-run-id-12345","status":200}
{"timestamp":"2026-07-15T00:38:06+00:00","method":"POST","uri":"/agent_listener/invoke_raw_method?method=log_event_data&...&run_id=mock-run-id-12345","status":200}
{"timestamp":"2026-07-15T00:38:36+00:00","method":"POST","uri":"/agent_listener/invoke_raw_method?method=metric_data&...&run_id=mock-run-id-12345","status":200}
```

## Key Discoveries

- **redirect_host format**: Must be IP/hostname without port (e.g., `"172.31.39.62"` not `"172.31.39.62:443"`)
- **Minimal response required**: Security policies in preconnect cause v6.5.0 and v9.3.0 to fail
- **SSL requirements**: Certificate must have SAN matching connection IP and be trusted in Java cacerts
- **Agent compatibility**: v9.3.0 works perfectly, v6.5.0 has internal bugs preventing custom backends

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

1. **Transform NewRelic data format** - Nginx needs to decompress gzip payloads and transform NewRelic JSON schema to Observe format
2. **Alternative: Observe NewRelic endpoint** - Check if Observe has a native NewRelic ingestion endpoint (like `/v1/newrelic`)
3. **Test OPAL queries** - Once data lands, write Observe queries to flatten NewRelic JSON into datastreams
4. **Performance testing** - Validate nginx can handle 200 services at production scale

## Current Blocker

**Observe HTTP 400 Errors - Data Format Incompatibility**

The nginx proxy successfully forwards NewRelic telemetry to Observe's `/v1/http/newrelic/` endpoint, but Observe returns HTTP 400 errors:

```json
{"timestamp":"2026-07-15T00:48:36+00:00","status":400,"body_bytes":94}
```

**Root Cause**: NewRelic agent sends proprietary protocol data:
- Gzip-compressed JSON payloads (`\u001F�\b` = gzip magic number)
- NewRelic-specific schema (agent_run_id, marshal_format, protocol_version)
- Methods: analytic_event_data, span_event_data, metric_data, transaction_sample_data

Observe's `/v1/http` endpoint expects generic telemetry formats (JSON, CSV, msgpack) but receives NewRelic's proprietary format.

**Potential Solutions**:
1. Add nginx Lua module to decompress and transform data before forwarding
2. Deploy separate transformer service between nginx and Observe
3. Check if Observe has NewRelic-compatible endpoint
4. Use OpenTelemetry collector to convert NewRelic → OTLP → Observe
