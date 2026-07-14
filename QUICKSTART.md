# Quick Start Guide

Get the NewRelic Observe proxy running in 15 minutes.

## Prerequisites

- AWS account with credentials
- EC2 key pair created
- Observe datastream token and endpoint

## Step 1: Configure Terraform

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
key_pair_name         = "your-ec2-key"
allowed_ssh_cidrs     = ["YOUR_IP/32"]
observe_token         = "ds1_xxx"
observe_endpoint_host = "123.collect.observeinc.com"
```

## Step 2: Deploy

```bash
terraform init
terraform apply
```

Note the output IPs.

## Step 3: Wait for Setup (~5 minutes)

User data scripts are installing Docker and starting services.

Monitor progress:
```bash
# Check nginx
ssh -i ~/.ssh/your-key.pem ec2-user@<nginx-ip> "tail -f /var/log/cloud-init-output.log"
```

## Step 4: Verify

```bash
# Test nginx
curl -k https://<nginx-ip>:443/health

# Test Java service
curl http://<java-service-ip>:8080/api/users
```

## Step 5: Generate Load

```bash
cd ../../validation
./generate-load.sh http://<java-service-ip>:8080 60 10
```

## Step 6: Check Results

```bash
./check-nginx-logs.sh <nginx-ip> ~/.ssh/your-key.pem
```

## Step 7: View in Observe

Log in to Observe and query your datastream. You should see NewRelic JSON payloads.

## Done!

Your simulation is running. Now:
1. Document findings in `docs/findings.md`
2. Test OPAL queries for data flattening
3. Plan production rollout

## Cleanup

```bash
cd infra/terraform
terraform destroy
```

## Troubleshooting

If services aren't starting, check user data logs:
```bash
ssh ec2-user@<ip> "cat /var/log/cloud-init-output.log"
```

If NewRelic agent isn't connecting:
```bash
ssh ec2-user@<java-ip> "docker logs java7-service | grep -i newrelic"
```

If nginx isn't capturing spans:
```bash
ssh ec2-user@<nginx-ip> "sudo tail -f /var/log/nginx/newrelic-spans.jsonl"
```
