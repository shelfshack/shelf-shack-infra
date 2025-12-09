# OpenSearch Disabled in AWS - Using PostgreSQL Fallback

## Summary

OpenSearch has been **disabled in AWS** to avoid free tier limitations and connection issues. The backend application will automatically use **PostgreSQL for search** when OpenSearch is unavailable.

**OpenSearch remains available for local development** via `docker-compose.yml`.

## What Was Changed

### Infrastructure (Terraform)

1. **Commented out OpenSearch modules** in `envs/dev/main.tf`:
   - `module.opensearch_nlb` - Internal Network Load Balancer
   - `module.opensearch_container` - OpenSearch ECS service
   - `module.opensearch_dashboards` - OpenSearch Dashboards service
   - Security group rules for OpenSearch

2. **Commented out Route53 records**:
   - `search.shelfshack.com` - OpenSearch endpoint
   - `dashboards.shelfshack.com` - Dashboards endpoint

3. **Updated outputs** in `envs/dev/outputs.tf`:
   - Commented out all OpenSearch-related outputs
   - Added `search_backend` output indicating PostgreSQL is in use

### Backend Application

**No changes needed!** The backend already has built-in fallback logic:

- When OpenSearch is unavailable, all search endpoints automatically fall back to PostgreSQL
- The application logs warnings but continues to function normally
- Search functionality works, just using PostgreSQL instead of OpenSearch

## How It Works

### Search Endpoints Behavior

All search endpoints (`/api/items/`, `/api/search/`, etc.) will:

1. **Try OpenSearch first** (if `OPENSEARCH_HOST` is set)
2. **Automatically fall back to PostgreSQL** if OpenSearch is unavailable
3. **Log warnings** but don't fail the request

### Local Development

OpenSearch is still available locally:

```bash
# Start local services including OpenSearch
docker-compose up -d

# OpenSearch will be available at http://localhost:9200
# Dashboards will be available at http://localhost:5601
```

The backend will automatically detect local OpenSearch and use it.

## Deployment Steps

1. **Review the changes**:
   ```bash
   cd envs/dev
   terraform plan
   ```

2. **Apply the changes**:
   ```bash
   terraform apply
   ```

   This will:
   - Destroy the OpenSearch container service (if it exists)
   - Destroy the OpenSearch NLB
   - Destroy the OpenSearch Dashboards service
   - Remove Route53 records for OpenSearch subdomains

3. **Verify the backend**:
   - Check ECS service logs - you should see warnings about OpenSearch being unavailable
   - Test search endpoints - they should work using PostgreSQL
   - No errors should occur - the app gracefully handles missing OpenSearch

## Re-enabling OpenSearch in AWS

If you want to re-enable OpenSearch later:

1. **Uncomment the modules** in `envs/dev/main.tf`:
   - `module.opensearch_nlb`
   - `module.opensearch_container`
   - `module.opensearch_dashboards`
   - Security group rules

2. **Uncomment Route53 records** for OpenSearch subdomains

3. **Set environment variables** in ECS service:
   ```hcl
   environment_variables = merge(local.environment_variables, {
     OPENSEARCH_HOST = module.opensearch_nlb.nlb_dns_name
     OPENSEARCH_PORT = "9200"
     OPENSEARCH_USE_SSL = "false"
     OPENSEARCH_VERIFY_CERTS = "false"
   })
   ```

4. **Deploy**:
   ```bash
   terraform apply
   ```

## Benefits

✅ **No connection errors** - Backend won't try to connect to non-existent OpenSearch  
✅ **Cost savings** - No OpenSearch infrastructure costs  
✅ **Simpler setup** - One less service to manage  
✅ **Still functional** - Search works via PostgreSQL  
✅ **Local dev unchanged** - OpenSearch still available locally  

## Search Performance

- **PostgreSQL search**: Works well for small to medium datasets
- **OpenSearch**: Better for large datasets, full-text search, and geo-queries

For production with large datasets, consider:
- Re-enabling OpenSearch when you have a paid AWS account
- Using AWS OpenSearch Service (managed)
- Or using the containerized version (current setup)

## Monitoring

Check backend logs for OpenSearch fallback messages:

```bash
# View ECS service logs
aws logs tail /ecs/rentify-dev --follow --region us-east-1

# Look for messages like:
# "OpenSearch unavailable, falling back to PostgreSQL for search"
```

These are **warnings, not errors** - the application is working correctly.

## Troubleshooting

### Backend still trying to connect to OpenSearch?

Check that no `OPENSEARCH_HOST` environment variable is set in ECS task definition.

### Search not working?

1. Check backend logs for errors
2. Verify PostgreSQL is accessible
3. Test a simple search endpoint: `GET /api/items/`

### Want to verify PostgreSQL search is working?

```bash
# Test search endpoint
curl https://api.shelfshack.com/api/items/?search=test

# Should return results from PostgreSQL
```

## Next Steps

1. Deploy the updated Terraform configuration
2. Verify search endpoints work with PostgreSQL
3. Monitor backend logs for any issues
4. Re-enable OpenSearch when ready (paid account, larger dataset, etc.)






