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

## Production Deployment

For production use with 200 services:

1. **High Availability Setup**
   - Deploy 2+ nginx instances
   - Add Application Load Balancer
   - Configure auto-scaling

2. **Update NewRelic Agent Config**
   ```yaml
   # newrelic.yml on each service
   common:
     host: 'nginx-proxy-lb.internal.com'
     port: 443
     ssl: true
   ```

3. **Rollout Plan**
   - Week 1: 10 pilot services
   - Week 2-4: Remaining 190 services in batches
   - Week 5+: Cancel NewRelic subscription

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
