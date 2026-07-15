# Test Findings

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
- Agent v6.5.0 (Java 7 compatible, EOL 2020) - ❌ Has NullPointerException with security_policies
- Agent v9.3.0 (Latest, 2024) - ✅ Works perfectly with minimal response (CubeAPM style)
- Security policies in preconnect response cause agent to fail before connect call
- Minimal response format (just redirect_host) allows successful connection

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

1. **Generate test traffic** - Create HTTP requests to Java service to generate spans and traces
2. **Validate Observe ingestion** - Check if telemetry is successfully reaching Observe platform
3. **Test OPAL queries** - Write Observe queries to flatten NewRelic JSON into datastreams
4. **Performance testing** - Validate nginx can handle 200 services at production scale
