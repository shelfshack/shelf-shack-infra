# Subdomains Setup Summary

## What Was Created

### New Modules

1. **`modules/opensearch_nlb/`** - Internal Network Load Balancer for OpenSearch
   - Provides stable endpoint for OpenSearch
   - Deployed in private subnets
   - TCP load balancer on port 9200

2. **`modules/opensearch_dashboards/`** - OpenSearch Dashboards Service
   - Deploys OpenSearch Dashboards container
   - Connects to OpenSearch via NLB
   - Can be exposed via ALB

### Updated Modules

1. **`modules/opensearch_container/`** - Updated to support NLB target group registration
2. **`modules/ecs_service/`** - Added ALB listener ARN outputs

### Infrastructure Changes

1. **Internal NLB** for OpenSearch (stable endpoint)
2. **OpenSearch Dashboards** service with ALB integration
3. **Route53 Records** for:
   - `api.shelfshack.com` → Backend API
   - `search.shelfshack.com` → OpenSearch (internal)
   - `dashboards.shelfshack.com` → OpenSearch Dashboards

## Subdomain Configuration

| Subdomain | Service | Type | Access |
|-----------|---------|------|--------|
| `api.shelfshack.com` | Backend FastAPI | ALB | Public |
| `search.shelfshack.com` | OpenSearch | Internal NLB | VPC-only |
| `dashboards.shelfshack.com` | OpenSearch Dashboards | ALB | Public |

## Quick Start

1. **Get Route53 Zone ID**:
   ```bash
   aws route53 list-hosted-zones --query "HostedZones[?Name=='shelfshack.com.'].Id" --output text
   ```

2. **Create ACM Certificate** (if not exists):
   - Request `*.shelfshack.com` certificate in ACM
   - Validate via DNS

3. **Update `terraform.tfvars`**:
   ```hcl
   enable_load_balancer = true
   enable_https = true
   route53_zone_id = "Z1234567890ABC"
   certificate_arn = "arn:aws:acm:us-east-1:ACCOUNT:certificate/CERT_ID"
   domain_name = "shelfshack.com"
   api_subdomain = "api"
   opensearch_subdomain = "search"
   dashboards_subdomain = "dashboards"
   ```

4. **Update Backend Environment Variables**:
   ```hcl
   app_environment = {
     # ... existing vars ...
     OPENSEARCH_HOST = "<nlb-dns-name>"  # Get from terraform output
     OPENSEARCH_PORT = "9200"
     OPENSEARCH_USE_SSL = "false"
     OPENSEARCH_VERIFY_CERTS = "false"
   }
   ```

5. **Deploy**:
   ```bash
   cd envs/dev
   terraform init
   terraform plan
   terraform apply
   ```

6. **Get NLB DNS Name**:
   ```bash
   terraform output opensearch_nlb_dns_name
   ```

## Files Modified

- `envs/dev/main.tf` - Added NLB, Dashboards, Route53 records
- `envs/dev/variables.tf` - Added domain configuration variables
- `envs/dev/outputs.tf` - Added domain endpoint outputs
- `modules/opensearch_container/` - Added NLB target group support
- `modules/opensearch_nlb/` - New module
- `modules/opensearch_dashboards/` - New module
- `modules/ecs_service/outputs.tf` - Added listener ARN outputs

## Documentation

- **`DOMAIN_SETUP_GUIDE.md`** - Complete setup guide with troubleshooting
- **`OPENSEARCH_CONTAINER_SETUP.md`** - OpenSearch container details
- **`QUICK_FIX_OPENSEARCH.md`** - Quick fix for connection issues

## Next Steps

1. Follow `DOMAIN_SETUP_GUIDE.md` for detailed setup
2. Update backend environment variables with NLB DNS name
3. Test endpoints after deployment
4. Configure authentication for Dashboards (recommended)

## Important Notes

- **OpenSearch is internal-only**: `search.shelfshack.com` only works from within VPC
- **Backend must use NLB DNS name**: Not the subdomain (subdomain is for VPC access only)
- **ALB required**: Must enable `enable_load_balancer = true` for API and Dashboards
- **HTTPS required**: Must enable `enable_https = true` and provide certificate ARN







