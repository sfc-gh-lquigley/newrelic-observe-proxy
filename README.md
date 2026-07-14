# NewRelic Observe Proxy

Nginx proxy that forwards NewRelic agent telemetry to Observe. Bridge solution for legacy Java 7 services during migration.

## Problem

You have 200 Java 7 services instrumented with NewRelic agents (v6.5.0), but need to:
- Migrate observability to Observe
- Avoid rushing Java 7 → Java 8+ upgrades in 3 months
- Eliminate NewRelic SaaS subscription costs

**Challenge:** OpenTelemetry requires Java 8+. No modern APM agent supports Java 7.

## Solution

Reconfigure existing NewRelic agents to send telemetry to a custom nginx endpoint, which forwards raw JSON to Observe's HTTP ingest. No application code changes required.

## Architecture

```
┌──────────────────────────────────┐
│  Java 7 Service                  │
│  ┌────────────────────────────┐  │
│  │ Your Application           │  │
│  │                            │  │
│  │  NewRelic Agent v6.5.0     │  │
│  │  (configured to nginx)     │  │
│  └──────────┬─────────────────┘  │
└─────────────┼─────────────────────┘
              │
              │ POST /agent_listener
              │ (NewRelic JSON)
              ▼
┌─────────────────────────────────────┐
│  Nginx Proxy                        │
│  - SSL termination                  │
│  - Mock NewRelic collector          │
│  - Forward to Observe               │
└──────────────┬──────────────────────┘
               │
               │ HTTP POST (raw JSON)
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
├── java-service/               # Test Java 7 service
│   ├── Dockerfile
│   ├── pom.xml
│   ├── src/
│   ├── newrelic/
│   │   ├── newrelic.yml
│   │   └── newrelic.jar        # v6.5.0
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

For each of your 200 Java 7 services, update the NewRelic agent configuration:

**Step 1: Update newrelic.yml**
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

**Step 2: Restart the service** to pick up new configuration.

**That's it** - no code changes, just config + restart per service.

### Phased Rollout Strategy

**DO NOT update all 200 services at once.** Use this timeline:

#### Week 1: Infrastructure + Pilot (10 services)

**Day 1-2: Deploy Infrastructure**
1. Deploy HA nginx setup with ALB
2. Configure DNS and SSL certificates
3. Set up monitoring/alerting
4. Load test nginx with expected throughput (200K spans/min)

**Day 3-5: Pilot Rollout**
1. Select 10 low-risk, non-critical services
2. Update their `newrelic.yml` and restart
3. Verify spans appear in Observe
4. Build initial OPAL queries for data flattening
5. Create dashboards for your team

**Day 6-7: Validation**
- Monitor pilot services for 48 hours
- Check for errors, dropped spans, performance issues
- Get team feedback on Observe vs NewRelic UI

**Go/No-Go Decision:** Proceed only if pilot is successful.

#### Week 2: First Wave (50 services)

**Batch 1 (25 services):**
- Update on Monday morning
- Monitor for 24 hours
- Fix any issues before next batch

**Batch 2 (25 services):**
- Update on Wednesday/Thursday
- Monitor for 24 hours

#### Week 3: Second Wave (80 services)

**Batch 3 (40 services):**
- Update Monday/Tuesday
- Monitor for 24 hours

**Batch 4 (40 services):**
- Update Thursday/Friday
- Monitor through weekend

#### Week 4: Final Wave (60 services)

**Batch 5 (30 services):**
- Update on Tuesday
- Monitor for 24 hours

**Batch 6 (30 services):**
- Update on Thursday
- Monitor through weekend

#### Week 5: Validation & Cleanup

1. **Verify all 200 services migrated**
   - Check service inventory
   - Confirm span volume matches expectations
   - No services still pointing to NewRelic SaaS

2. **Performance validation**
   - Review nginx capacity metrics
   - Check Observe ingest is stable
   - Verify OPAL queries performing well

3. **Cancel NewRelic subscription**
   - Export any historical data you need
   - Close NewRelic account
   - Remove NewRelic endpoints from network allowlists

### Capacity Planning

**Expected load for 200 services:**
- Assume ~1000 spans/min per service
- Total: 200K spans/min = 3,333 spans/sec

**Nginx sizing:**
- 2× t3.large (2 vCPU, 8GB) can handle ~5K req/sec
- Add 3rd instance for headroom
- Enable auto-scaling for traffic spikes

**Network bandwidth:**
- Each span ~2KB
- 200K spans/min × 2KB = ~400MB/min = ~7MB/sec
- Ensure ALB and nginx have sufficient bandwidth

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

If issues arise, **rollback is simple per service:**

**Revert newrelic.yml:**
```yaml
# Change back to NewRelic SaaS
common:
  host: 'collector.newrelic.com'
  port: 443
  license_key: '<real-newrelic-key>'
```

**Restart service** - it immediately reconnects to NewRelic SaaS.

**Keep NewRelic subscription active** until all 200 services are stable on the new proxy for 2+ weeks.

### Timeline & Costs

**Timeline:** 5 weeks for full migration
- Week 1: Infrastructure + pilot (10 services)
- Week 2-4: Phased rollout (190 services)
- Week 5: Validation + cleanup

**Infrastructure Costs:**
- 3× t3.large nginx instances: ~$150/month
- Application Load Balancer: ~$30/month
- Data transfer: ~$20/month
- **Total: ~$200/month**

**Savings:**
- NewRelic SaaS subscription cancellation
- Net savings = (NewRelic cost) - $200/month

### Post-Migration

After successful migration:

1. **Document the architecture** for future team members
2. **Update runbooks** with new debugging workflows
3. **Archive NewRelic historical data** if needed
4. **Establish SLAs** for nginx proxy uptime
5. **Plan for Java 8+ migration** (longer-term)

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
