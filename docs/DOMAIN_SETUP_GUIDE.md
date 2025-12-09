# Domain Setup Guide: shelfshack.com Subdomains

This guide explains how to set up subdomains for your services using the `shelfshack.com` domain.

## ⚠️ Important: AWS Free Tier Limitations

**Load balancers (ALB/NLB) are NOT included in AWS Free Tier** and will incur costs:
- **ALB**: ~$16/month per load balancer
- **NLB**: ~$16/month per load balancer
- **Data transfer**: Additional charges apply

### For Free Tier Users

If you're on AWS Free Tier, you have two options:

#### Option 1: Skip Load Balancers (Recommended for Free Tier)
- Keep `enable_load_balancer = false` in `terraform.tfvars`
- Access services via:
  - **Public IPs**: If tasks have public IPs assigned
  - **ECS Exec**: Access services from within VPC
  - **Bastion Host**: SSH tunnel for external access
  - **Service Discovery**: Use AWS Cloud Map for stable DNS (free)

#### Option 2: Enable Load Balancers (Paid)
- You will be charged ~$32-48/month for load balancers
- Follow this guide to set up subdomains with load balancers
- Suitable for production or when you have a paid AWS account

## Overview

After setup (with load balancers enabled), you'll have:
- **API**: `api.shelfshack.com` → Backend FastAPI service
- **OpenSearch**: `search.shelfshack.com` → OpenSearch container (internal, VPC-only)
- **Dashboards**: `dashboards.shelfshack.com` → OpenSearch Dashboards

## Prerequisites

1. **Route53 Hosted Zone**: Your domain `shelfshack.com` must be in Route53
2. **ACM Certificate**: SSL certificate for `*.shelfshack.com` (or specific subdomains)
3. **ALB Enabled**: Load balancer must be enabled for API and Dashboards (`enable_load_balancer = true`)

## Step 1: Get Route53 Hosted Zone ID

```bash
aws route53 list-hosted-zones --query "HostedZones[?Name=='shelfshack.com.'].Id" --output text
```

This will return something like: `/hostedzone/Z1234567890ABC`

## Step 2: Create ACM Certificate

Create a certificate in ACM for your subdomains:

```bash
# Request certificate for wildcard domain
aws acm request-certificate \
  --domain-name "*.shelfshack.com" \
  --subject-alternative-names "shelfshack.com" \
  --validation-method DNS \
  --region us-east-1
```

Or via AWS Console:
1. Go to ACM → Request Certificate
2. Request public certificate
3. Add domain: `*.shelfshack.com`
4. Add alternative name: `shelfshack.com`
5. Choose DNS validation
6. Add the CNAME records to Route53 for validation

Get the certificate ARN after validation:
```bash
aws acm list-certificates --region us-east-1 --query "CertificateSummaryList[?DomainName=='*.shelfshack.com'].CertificateArn" --output text
```

## Step 3: Update Terraform Variables

Update `envs/dev/terraform.tfvars`:

```hcl
# Enable load balancer
enable_load_balancer = true

# Enable HTTPS
enable_https = true

# Route53 configuration
route53_zone_id = "Z1234567890ABC"  # Your hosted zone ID from Step 1
certificate_arn = "arn:aws:acm:us-east-1:ACCOUNT_ID:certificate/CERT_ID"  # From Step 2

# Domain configuration
domain_name = "shelfshack.com"
api_subdomain = "api"              # Creates api.shelfshack.com
opensearch_subdomain = "search"   # Creates search.shelfshack.com
dashboards_subdomain = "dashboards"  # Creates dashboards.shelfshack.com
```

## Step 4: Update Backend Environment Variables

The backend needs to connect to OpenSearch via the NLB. Update your backend environment variables:

```hcl
app_environment = {
  # ... existing variables ...
  
  # OpenSearch configuration - use NLB DNS name
  OPENSEARCH_HOST = "<nlb-dns-name>"  # Will be: rentify-dev-opensearch-nlb-xxxxx.elb.us-east-1.amazonaws.com
  OPENSEARCH_PORT = "9200"
  OPENSEARCH_USE_SSL = "false"
  OPENSEARCH_VERIFY_CERTS = "false"
}
```

**To get the NLB DNS name after deployment:**
```bash
aws elbv2 describe-load-balancers \
  --region us-east-1 \
  --query "LoadBalancers[?LoadBalancerName=='rentify-dev-opensearch-nlb'].DNSName" \
  --output text
```

Or use Terraform output:
```bash
cd envs/dev
terraform output opensearch_nlb_dns_name
```

## Step 5: Deploy Infrastructure

```bash
cd envs/dev
terraform init
terraform plan  # Review changes
terraform apply
```

## Step 6: Verify DNS Records

After deployment, verify the DNS records were created:

```bash
# Check API subdomain
dig api.shelfshack.com

# Check Dashboards subdomain
dig dashboards.shelfshack.com

# Check OpenSearch subdomain (will only resolve from within VPC)
dig search.shelfshack.com
```

## Step 7: Test Endpoints

### API Endpoint
```bash
curl https://api.shelfshack.com/health
```

### OpenSearch Endpoint
```bash
# From within VPC or via bastion
curl http://search.shelfshack.com:9200/_cluster/health
```

**Note**: OpenSearch is internal-only. To access from outside:
1. Use VPN to connect to VPC
2. Use bastion host with port forwarding
3. Use ECS Exec to access from within VPC

### Dashboards Endpoint
```bash
# Open in browser
https://dashboards.shelfshack.com
```

## Architecture

```
Internet
   │
   ├─→ api.shelfshack.com → ALB → Backend ECS Service
   │
   ├─→ dashboards.shelfshack.com → ALB → OpenSearch Dashboards ECS Service
   │
   └─→ search.shelfshack.com → Internal NLB → OpenSearch ECS Service
       (VPC-only, not accessible from internet)
```

## Security Considerations

1. **API Endpoint**: Publicly accessible (protected by your application authentication)
2. **Dashboards Endpoint**: Publicly accessible (consider adding authentication)
3. **OpenSearch Endpoint**: Internal only (VPC-only access)

### Recommended: Add Authentication to Dashboards

Consider adding:
- Basic authentication via ALB
- OAuth integration
- IP whitelist via security groups

## Troubleshooting

### DNS Not Resolving

1. Check Route53 records were created:
   ```bash
   aws route53 list-resource-record-sets \
     --hosted-zone-id Z1234567890ABC \
     --query "ResourceRecordSets[?Name | contains(@, 'api.shelfshack.com')]"
   ```

2. Verify certificate validation completed:
   ```bash
   aws acm describe-certificate \
     --certificate-arn <cert-arn> \
     --region us-east-1
   ```

### ALB Health Checks Failing

1. Check target group health:
   ```bash
   aws elbv2 describe-target-health \
     --target-group-arn <tg-arn> \
     --region us-east-1
   ```

2. Check ECS service logs:
   ```bash
   aws logs tail /ecs/rentify-dev --follow --region us-east-1
   ```

### OpenSearch Connection Issues

1. Verify NLB target group has healthy targets:
   ```bash
   aws elbv2 describe-target-health \
     --target-group-arn <nlb-tg-arn> \
     --region us-east-1
   ```

2. Check security group rules allow traffic from backend to NLB

3. Verify backend environment variables are set correctly

## Updating Subdomain Names

To change subdomain names, update `terraform.tfvars`:

```hcl
api_subdomain = "api"           # Change to "backend" for backend.shelfshack.com
opensearch_subdomain = "search" # Change to "opensearch" for opensearch.shelfshack.com
dashboards_subdomain = "dashboards" # Change to "kibana" for kibana.shelfshack.com
```

Then run `terraform apply`.

## Cost Considerations

- **ALB**: ~$16/month per ALB
- **NLB**: ~$16/month per NLB
- **Route53**: $0.50/month per hosted zone + $0.40 per million queries
- **ACM Certificate**: Free (one per account)

Total additional cost: ~$32-33/month for load balancers

## Free Tier Alternatives (Without Load Balancers)

If you're on AWS Free Tier and want to avoid load balancer costs, here are alternatives:

### Option 1: Access via Public IPs

If your ECS tasks have public IPs (`assign_public_ip = true`):

1. Get the public IP of your backend service:
   ```bash
   # Get task ARN
   TASK_ARN=$(aws ecs list-tasks \
     --cluster rentify-dev-cluster \
     --service-name rentify-dev-service \
     --query 'taskArns[0]' \
     --output text)
   
   # Get public IP
   aws ecs describe-tasks \
     --cluster rentify-dev-cluster \
     --tasks $TASK_ARN \
     --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
     --output text | xargs -I {} aws ec2 describe-network-interfaces \
     --network-interface-ids {} \
     --query 'NetworkInterfaces[0].Association.PublicIp' \
     --output text
   ```

2. Access directly: `http://<PUBLIC_IP>:8000`

**Note**: IPs change when tasks restart. Not ideal for production.

### Option 2: Use Route53 with Public IPs (Dynamic DNS)

1. Create a script that updates Route53 A record with current public IP
2. Run via cron or Lambda function
3. Access via: `api.shelfshack.com` (points to current public IP)

**Cost**: Route53 queries only (~$0.40 per million)

### Option 3: Use AWS Cloud Map Service Discovery (Free)

1. Enable service discovery in ECS service module
2. Services get stable DNS names: `<service-name>.<namespace>.local`
3. Access from within VPC using service discovery DNS

**Cost**: Free (included in ECS)

### Option 4: Use Bastion Host for External Access

1. SSH to bastion host
2. Port forward to ECS tasks
3. Access services via localhost

**Cost**: Only EC2 instance cost (t2.micro is free tier eligible)

### Option 5: Use ECS Exec for Internal Access

Access services directly from within VPC:

```bash
aws ecs execute-command \
  --cluster rentify-dev-cluster \
  --task <task-id> \
  --container <container-name> \
  --interactive \
  --command "/bin/bash"
```

Then from within the container, access other services via private IPs.

### Recommended Free Tier Setup

1. **Backend API**: Use public IPs or Route53 dynamic DNS
2. **OpenSearch**: Use private IPs (already configured via `get_opensearch_endpoint.sh`)
3. **Dashboards**: Access via bastion host port forwarding or ECS Exec

Example terraform.tfvars for free tier:
```hcl
enable_load_balancer = false  # Keep disabled
assign_public_ip = true       # Enable for direct access
```

## Next Steps

1. Set up monitoring and alerts for your endpoints
2. Configure CloudFront for API caching (optional)
3. Set up WAF rules for API protection
4. Add authentication to Dashboards endpoint
5. Configure backup and disaster recovery







