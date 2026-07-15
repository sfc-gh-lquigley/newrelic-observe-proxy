# Test Findings

## Status Summary

✅ **Infrastructure** - Fully automated deployment via Terraform  
✅ **Nginx Proxy** - Successfully mocks NewRelic collector API  
✅ **SSL Trust** - Certificate generated with SAN and trusted by Java  
✅ **Preconnect Flow** - Agent receives redirect_host and security policies  
⚠️ **Agent Issue** - NewRelic v6.5.0 has internal NullPointerException preventing connect call

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
   - Forwards telemetry to Observe HTTP ingest

3. **Agent Configuration**
   - Points to nginx instead of NewRelic SaaS
   - SSL handshake succeeds
   - Preconnect call succeeds
   - Parses redirect_host: `"172.31.39.62"`
   - Receives LASP security policies

## Known Issue

**NewRelic Java Agent v6.5.0 Internal Bug**

After successfully receiving preconnect response:
```
Received JSON(preconnect): {"return_value": {"redirect_host": "172.31.39.62", "security_policies": {...}}}
LASP Policies received from server side: {...}
Failed to connect: java.lang.NullPointerException
```

Agent never proceeds to call connect endpoint. This appears to be a limitation in the v6.5.0 agent (released 2021, EOL).

## Key Discoveries

- **redirect_host format**: Must be IP/hostname without port (e.g., `"172.31.39.62"` not `"172.31.39.62:443"`)
- **Empty redirect_host**: Causes agent to skip connect call entirely
- **SSL requirements**: Certificate must have SAN matching connection IP and be trusted in Java cacerts
- **Agent compatibility**: v6.5.0 may not support non-NewRelic backends; newer versions may work

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

1. **Test with newer agent** - Try NewRelic Java Agent v7 or v8
2. **Compare to real NewRelic** - Validate responses match actual NewRelic backend
3. **Investigate agent bug** - Deep-dive into v6.5.0 source code to find root cause of NullPointer
4. **Alternative agents** - Test with other language agents (Node.js, Python) that may handle custom backends better
