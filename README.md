# NewRelic Observe Proxy

Nginx proxy that forwards NewRelic agent telemetry to Observe. Bridge solution for legacy Java 7 services during migration.

## Agent Version Compatibility

**Critical Finding**: NewRelic agent version significantly impacts custom backend compatibility.

| Version | Status | Notes |
|---------|--------|-------|
| **v6.5.0** (2020, EOL) | ❌ **Doesn't Work** | Internal NullPointerException after preconnect. Never calls connect endpoint. Last Java 7 compatible version. |
| **v9.3.0** (2024, latest) | ✅ **Works** | Successfully connects with minimal preconnect response. Sends all telemetry data. |

**Recommendation**: Use v9.3.0 if your applications support Java 8+. If stuck on Java 7, this solution may not work with v6.5.0 without agent patching.

## Problem

You have 200 Java 7 services instrumented with NewRelic agents, but need to:
- Migrate observability to Observe
- Avoid rushing Java upgrades in 3 months
- Eliminate NewRelic SaaS subscription costs

**Challenge:** OpenTelemetry requires Java 8+. No modern APM agent supports Java 7. NewRelic v6.5.0 (last Java 7 agent) has bugs preventing custom backend usage.

## Solution

Reconfigure existing NewRelic agents to send telemetry to a custom nginx endpoint, which forwards raw JSON to Observe's HTTP ingest. No application code changes required.

**Agent Requirements**: 
- **Preferred**: Upgrade to NewRelic v9.3.0 (requires Java 8+) - fully tested and working
- **Java 7 fallback**: v6.5.0 has compatibility issues; may require custom agent patches or alternative approach

## Architecture

```
┌──────────────────────────────────┐
│  Java 7/8 Service                │
│  ┌────────────────────────────┐  │
│  │ Your Application           │  │
│  │                            │  │
│  │  NewRelic Agent v9.3.0     │  │
│  │  (configured to nginx)     │  │
│  └──────────┬─────────────────┘  │
└─────────────┼─────────────────────┘
              │
              │ POST /agent_listener
              │ (NewRelic JSON + gzip)
              ▼
┌─────────────────────────────────────┐
│  Nginx Proxy                        │
│  - SSL termination                  │
│  - Mock NewRelic collector          │
│  - Forward to Observe               │
└──────────────┬──────────────────────┘
               │
               │ HTTP POST (gzip JSON)
               ▼
       ┌──────────────┐
       │   Observe    │
       │ HTTP Ingest  │
       └──────────────┘
```

## What Gets Forwarded

NewRelic agents send span events in this JSON structure:

```json
[
  "license_key_string",
  {
    "reservoir_size": 10000,
    "events_seen": 1
  },
  [
    [
      {
        "type": "Span",
        "traceId": "abc123def456",
        "guid": "span123",
        "parentId": "parent456",
        "name": "WebTransaction/Servlet/UsersServlet",
        "timestamp": 1626789012345,
        "duration": 0.123,
        "category": "http"
      },
      {},
      {
        "http.method": "GET",
        "http.url": "https://example.com/api/users",
        "http.statusCode": 200
      }
    ]
  ]
]
```

**Array structure:**
- `[0]` - License key (string)
- `[1]` - Metadata
- `[2]` - Span events array
  - Each span: `[intrinsic_attrs, agent_attrs, user_attrs]`

## Repository Structure

```
newrelic-observe-proxy/
├── README.md                   # This file
├── docs/
│   └── findings.md             # Test results
├── java-service/               # Test Java 7/8 service
│   ├── Dockerfile
│   ├── pom.xml
│   ├── src/
│   ├── newrelic/
│   │   ├── newrelic.yml
│   │   └── newrelic.jar        # v9.3.0 (downloaded at build)
│   └── run.sh
├── nginx-proxy/                # Nginx configuration
│   ├── nginx.conf
│   ├── ssl/
│   └── Dockerfile
├── infra/                      # AWS deployment
│   ├── terraform/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── user-data/
├── validation/                 # Testing scripts
│   ├── generate-load.sh
│   └── check-nginx-logs.sh
└── .gitignore
```

## Quick Start

### Prerequisites

- AWS account with credentials configured
- Terraform installed
- Observe account with HTTP ingest endpoint and token

### 1. Deploy Infrastructure

```bash
cd infra/terraform

# Configure Observe credentials
export TF_VAR_observe_token="your-datastream-token"
export TF_VAR_observe_endpoint="https://123456789012.collect.observeinc.com/v1/http"

terraform init
terraform apply

# Note the output IPs
```

### 2. Generate Test Traffic

```bash
cd validation
./generate-load.sh http://<java-service-ip>:8080
```

### 3. Verify Data in Observe

Navigate to Observe UI and query the HTTP ingest logs. You should see raw NewRelic JSON events.

### 4. Flatten Data with OPAL

```sql
-- Example: Extract spans from NewRelic JSON
flatten(body[2]) as span_array
make_col trace_id:span_array[0].traceId
make_col span_name:span_array[0].name
make_col duration:span_array[0].duration
make_col http_method:span_array[2]["http.method"]
```

## Production Deployment at Scale

Deploying this solution for 200 Java 7 services requires careful planning and phased rollout.

### Infrastructure Requirements

The simulation uses single EC2 instances. For production, you need:

#### 1. High Availability Nginx Setup

**Deploy 2-3 nginx proxy instances** across multiple AZs:
- Use Auto Scaling Group (min: 2, desired: 2-3, max: 5)
- Enable auto-scaling based on CPU or request count
- Deploy in private subnets with NAT gateway

**Add Application Load Balancer:**
```hcl
# Add to Terraform
resource "aws_lb" "nginx_proxy" {
  name               = "newrelic-proxy-alb"
  internal           = true
  load_balancer_type = "application"
  subnets            = var.private_subnet_ids
  
  # Health check on /health endpoint
}
```

**Create internal DNS record:**
```bash
# Route53 internal hosted zone
newrelic-proxy.internal.yourcompany.com → ALB DNS
```

#### 2. SSL Certificates

**Replace self-signed certificates** with CA-signed:
- Use AWS Certificate Manager (ACM) for ALB
- Use Let's Encrypt or internal CA for nginx
- Import certificate to Java truststore on all 200 service hosts

#### 3. Monitoring & Alerting

**CloudWatch alarms:**
- Nginx instance health (from ALB target group)
- CPU utilization > 70%
- Memory utilization > 80%
- Request count spikes

**Observe integration:**
- Monitor ingest lag
- Alert on failed forwards to Observe
- Dashboard showing spans/sec throughput

**Key metrics to track:**
- Spans received vs forwarded (should match)
- Nginx response time (should be < 50ms)
- Observe ingest latency

### Service Configuration Rollout

For each of your 200 services, update the NewRelic agent configuration:

**Step 1: Upgrade Agent (if needed)**
If services are on Java 8+, upgrade to NewRelic v9.3.0:
```bash
wget https://download.newrelic.com/newrelic/java-agent/newrelic-agent/current/newrelic-java.zip
unzip newrelic-java.zip
# Replace old newrelic.jar with new version
```

**Step 2: Update newrelic.yml**
```yaml
# OLD (NewRelic SaaS)
common:
  host: 'collector.newrelic.com'
  port: 443
  license_key: '<real-newrelic-key>'

# NEW (Custom proxy)
common:
  host: 'newrelic-proxy.internal.yourcompany.com'
  port: 443
  ssl: true
  license_key: 'dummy-key-12345'  # Not validated
```

**Step 3: Restart the service** to pick up new configuration.

**That's it** - no code changes required (though agent upgrade recommended if on Java 8+).

### Rollout Strategy

**DO NOT update all 200 services at once.** Start with 10 pilot services, then roll out in batches (e.g., 25-50 services per batch). Wait 24 hours between batches to catch issues early. Expect 4-5 weeks total.

**Capacity planning:** 200 services × 1000 spans/min = 200K spans/min (3,333/sec). Use 2-3× t3.large nginx instances with auto-scaling.

### Pre-Flight Checklist

Before starting rollout, verify:

- [ ] HA nginx infrastructure deployed
- [ ] ALB health checks passing
- [ ] DNS record resolves correctly
- [ ] SSL certificates valid and trusted
- [ ] Monitoring/alerting configured
- [ ] Load test passed (simulate 200K spans/min)
- [ ] Observe confirmed ready for ingest volume
- [ ] OPAL queries tested and documented
- [ ] Rollback plan documented
- [ ] Team trained on new Observe workflows

### Per-Batch Checklist

**Before updating each batch:**
- [ ] Nginx proxy healthy
- [ ] Previous batch stable for 24+ hours
- [ ] No open incidents

**After updating each batch:**
- [ ] All services in batch restarted successfully
- [ ] Spans appearing in Observe for all services
- [ ] Span volume matches expected (~1000/min per service)
- [ ] No errors in nginx logs
- [ ] Services responding normally to requests

### Potential Issues & Solutions

#### Issue: Certificate Trust Errors

**Symptom:** Agent logs show SSL handshake failures

**Solution:** Import proxy certificate to Java truststore on each host
```bash
keytool -import -alias newrelic-proxy \
  -file /path/to/proxy-cert.pem \
  -keystore $JAVA_HOME/jre/lib/security/cacerts \
  -storepass changeit
```

Consider automating this with Ansible/Salt/Puppet across all hosts.

#### Issue: Nginx Capacity

**Symptom:** Nginx CPU > 80%, increased latency

**Solution:**
- Auto-scaling triggers new instance
- Verify you're not hitting ALB limits
- Check for slow requests to Observe

#### Issue: Observe Rate Limiting

**Symptom:** 429 errors in nginx logs

**Solution:**
- Contact Observe to increase rate limits
- Implement nginx request queuing/retry
- Slow down rollout to reduce burst

#### Issue: Spans Lost During Migration

**Symptom:** Gap in observability during service restart

**Solution:**
- This is expected - NewRelic agents buffer spans in memory
- Brief gaps (< 1 min) during restart are normal
- Not a data corruption issue

#### Issue: Services Can't Be Restarted Easily

**Symptom:** Manual restart process, no automation

**Solution:**
- Use deployment tools (Ansible, Chef, Puppet)
- Or update config via config management
- Or coordinate with service owners for manual restarts

### Rollback Plan

If issues arise, rollback is simple per service - revert `newrelic.yml` to point back to `collector.newrelic.com` and restart. Keep NewRelic subscription active until all services are stable on the new proxy for 2+ weeks.

### Timeline & Costs

**Timeline:** 4-5 weeks  
**Infrastructure:** ~$200/month (3× t3.large + ALB + data transfer)  
**Savings:** Your NewRelic subscription cost - $200/month

## Costs

- **Current:** NewRelic SaaS subscription (~$X/month)
- **New:** AWS nginx HA (~$60/month) + Observe (existing contract)
- **Savings:** $X - $60/month

## Monitoring

Monitor nginx health:
- CloudWatch metrics (CPU, memory, network)
- Nginx access logs (`/var/log/nginx/newrelic-raw.jsonl`)
- Observe ingest rate

## Troubleshooting

### Agent won't connect to nginx

Check `newrelic.yml` configuration and verify nginx is listening on port 443.

### No data in Observe

1. Check nginx logs: `tail -f /var/log/nginx/newrelic-raw.jsonl`
2. Verify Observe token and endpoint
3. Test nginx → Observe forwarding manually

### SSL certificate errors

Ensure nginx certificate is trusted by Java 7 keystore, or use self-signed cert added to Java truststore.

## License

MIT

## Contributing

This is a simulation/validation project. For production use, adjust based on your specific requirements.
