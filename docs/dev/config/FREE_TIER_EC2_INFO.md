# AWS Free Tier EC2 Instance Types

## Free Tier Eligibility

**Depends on when your AWS account was created:**

### Accounts Created BEFORE July 15, 2025
- ✅ `t2.micro` (750 hours/month)
- ✅ `t3.micro` (750 hours/month)
- ❌ `t3.small` - **NOT free** (costs ~$0.0208/hour)

### Accounts Created ON/AFTER July 15, 2025
- ✅ `t3.micro` (750 hours/month)
- ✅ `t3.small` (750 hours/month) - **NEW!**
- ✅ `t4g.micro` (750 hours/month)
- ✅ `t4g.small` (750 hours/month)
- ✅ `c7i-flex.large` (750 hours/month)
- ✅ `m7i-flex.large` (750 hours/month)

## Check Your Account

Run this to see what's available for YOUR account:

```bash
aws ec2 describe-instance-types \
  --filters Name=free-tier-eligible,Values=true \
  --query "InstanceTypes[*].[InstanceType]" \
  --output text | sort
```

## Recommendations

### If t3.small is FREE for you:
**Upgrade to t3.small** - it has 2GB RAM (vs 1GB for t3.micro):

```hcl
# In terraform.tfvars
opensearch_ec2_instance_type = "t3.small"
opensearch_ec2_java_heap_size = "512m"  # Can use more with 2GB RAM
```

Then:
```bash
terraform taint module.opensearch_ec2[0].aws_instance.opensearch
terraform apply -var-file=terraform.tfvars
```

### If t3.small is NOT free:
**Options:**

1. **Stick with t3.micro + 128m heap** (current fix)
   - Should work, but tight
   - Monitor for OOM kills

2. **Use t4g.micro** (if available)
   - ARM-based, same 1GB RAM
   - Might be more efficient
   - Change: `opensearch_ec2_instance_type = "t4g.micro"`

3. **Accept minimal cost**
   - t3.small costs ~$0.0208/hour = ~$15/month if running 24/7
   - For dev, you can stop it when not in use
   - Only pay for hours used

4. **Consider alternatives**
   - Use OpenSearch only when needed
   - Use a managed service (not free)
   - Use a lighter search solution

## Free Tier Limits

- **750 hours/month** of eligible instance types
- **12 months** from account creation
- After 12 months, you pay standard rates
- Multiple instances share the 750 hours (e.g., 2 instances = 375 hours each)

## Cost Estimate (if not free)

- **t3.micro**: ~$0.0104/hour = ~$7.50/month (24/7)
- **t3.small**: ~$0.0208/hour = ~$15/month (24/7)

For dev, you can stop instances when not in use to save costs.
