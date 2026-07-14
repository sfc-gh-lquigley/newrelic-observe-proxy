# Infrastructure - AWS Deployment

Terraform configuration to deploy the NewRelic Observe proxy simulation to AWS.

## What Gets Created

- **2× EC2 instances** (t3.small by default)
  - Nginx proxy instance
  - Java 7 service instance
- **2× Elastic IPs** (for stable addressing)
- **2× Security groups** (for firewall rules)
- **User data scripts** (automated setup on boot)

## Prerequisites

1. **AWS Account** with credentials configured
2. **AWS CLI** installed and configured
3. **Terraform** v1.0+ installed
4. **EC2 Key Pair** created in your AWS region
5. **Observe credentials** (datastream token and endpoint)

## Setup

### 1. Configure AWS Credentials

```bash
aws configure
# Enter your AWS access key, secret key, and region
```

### 2. Create terraform.tfvars

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
aws_region            = "us-west-2"
key_pair_name         = "my-key-pair"
allowed_ssh_cidrs     = ["YOUR_IP/32"]
observe_token         = "ds1..."
observe_endpoint_host = "123456789012.collect.observeinc.com"
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Plan Deployment

```bash
terraform plan
```

Review the resources that will be created.

### 5. Deploy

```bash
terraform apply
```

Type `yes` to confirm.

## Deployment takes ~5 minutes

- EC2 instances boot
- User data scripts run
- Docker containers start
- Services become available

## Accessing Instances

After deployment, Terraform outputs connection commands:

```bash
# SSH to nginx proxy
ssh -i ~/.ssh/your-key.pem ec2-user@<nginx-ip>

# SSH to Java service
ssh -i ~/.ssh/your-key.pem ec2-user@<java-service-ip>
```

## Verifying Deployment

### Check nginx proxy

```bash
# Health check
curl -k https://<nginx-ip>:443/health

# View logs
ssh ec2-user@<nginx-ip>
docker logs newrelic-proxy
tail -f /var/log/nginx/newrelic-spans.jsonl
```

### Check Java service

```bash
# Test API
curl http://<java-service-ip>:8080/api/users

# View logs
ssh ec2-user@<java-service-ip>
docker logs java7-service
docker exec java7-service cat logs/newrelic_agent.log
```

## Architecture

```
Internet
    │
    ├─► EC2: Nginx Proxy (port 443)
    │     - Receives NewRelic agent traffic
    │     - Forwards to Observe
    │     - Logs payloads
    │
    └─► EC2: Java 7 Service (port 8080)
          - Test application
          - NewRelic agent → nginx
```

## Security Groups

### Nginx Proxy
- **Inbound:**
  - 443 (HTTPS) from anywhere
  - 22 (SSH) from allowed_ssh_cidrs
- **Outbound:**
  - All traffic (for Observe)

### Java Service
- **Inbound:**
  - 8080 (HTTP) from anywhere
  - 22 (SSH) from allowed_ssh_cidrs
- **Outbound:**
  - All traffic (for nginx)

## Costs

| Resource | Type | Monthly Cost |
|----------|------|--------------|
| EC2 nginx | t3.small | ~$15 |
| EC2 Java | t3.small | ~$15 |
| Elastic IPs | 2× | ~$7 |
| Data transfer | ~10GB | ~$1 |
| **Total** | | **~$38/month** |

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

Type `yes` to confirm.

**This will delete:**
- Both EC2 instances
- Elastic IPs
- Security groups
- All data

## Troubleshooting

### Instances not starting

Check user data execution:

```bash
ssh ec2-user@<instance-ip>
cat /var/log/cloud-init-output.log
```

### Docker not running

```bash
ssh ec2-user@<instance-ip>
sudo systemctl status docker
sudo systemctl start docker
```

### Can't connect to instances

- Verify security group rules
- Check your IP is in `allowed_ssh_cidrs`
- Confirm key pair name matches your local key

### Nginx not forwarding to Observe

- Verify `OBSERVE_TOKEN` is correct
- Check `OBSERVE_ENDPOINT_HOST` is just the hostname (no https://)
- View nginx logs for errors

## Production Considerations

For production use, modify:

1. **HA Setup** - Deploy 2+ nginx instances with load balancer
2. **Monitoring** - Add CloudWatch alarms
3. **Backups** - Enable EBS snapshots
4. **SSL** - Use proper CA-signed certificates
5. **Security** - Restrict SSH to bastion host only
6. **Networking** - Deploy in private subnets with NAT gateway
