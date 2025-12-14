# EC2 Instance Cost Analysis for OpenSearch

## Free Tier Eligibility

### ✅ Within Free Tier (First 12 Months)
For accounts created **on or after July 15, 2025**, the following are **FREE** (750 hours/month):

- `t3.micro` (1GB RAM) - FREE
- `t3.small` (2GB RAM) - FREE  
- `t4g.micro` (1GB RAM, ARM) - FREE
- `t4g.small` (2GB RAM, ARM) - FREE
- `c7i-flex.large` (4GB RAM) - FREE
- **`m7i-flex.large` (8GB RAM) - FREE** ✅ **Currently Using**

### Important Points:
1. **All eligible instance types cost the SAME in Free Tier** - $0.00
2. **750 hours/month** = ~31 days of continuous usage
3. **Multiple instances share the 750 hours** (e.g., 2 instances = 375 hours each)
4. **After 12 months**, Free Tier expires and you pay standard rates

## Cost Comparison: Free Tier vs. Paid

### Current Configuration: `m7i-flex.large`

| Period | Cost | Notes |
|--------|------|-------|
| **Free Tier (first 12 months)** | **$0.00/month** | Up to 750 hours/month |
| **After Free Tier** | **~$0.134/hour** | ~$97/month (24/7) |

### Alternative: `t3.small`

| Period | Cost | Notes |
|--------|------|-------|
| **Free Tier (first 12 months)** | **$0.00/month** | Up to 750 hours/month |
| **After Free Tier** | **~$0.0208/hour** | ~$15/month (24/7) |

## Cost Breakdown (Outside Free Tier)

### m7i-flex.large (8GB RAM, 2 vCPU)
- **On-Demand**: ~$0.134/hour
- **Monthly (24/7)**: ~$97.20/month
- **Monthly (730 hours)**: ~$97.82/month
- **Best for**: Production workloads, better performance

### t3.small (2GB RAM, 2 vCPU)
- **On-Demand**: ~$0.0208/hour
- **Monthly (24/7)**: ~$15.00/month
- **Monthly (730 hours)**: ~$15.18/month
- **Best for**: Dev/test, cost-effective

### t3.micro (1GB RAM, 2 vCPU)
- **On-Demand**: ~$0.0104/hour
- **Monthly (24/7)**: ~$7.50/month
- **Monthly (730 hours)**: ~$7.59/month
- **Best for**: Minimal workloads (may have memory issues)

## Additional Costs (Outside Free Tier)

### EBS Storage
- **gp3 (default)**: ~$0.08/GB/month
- **Example**: 20GB = ~$1.60/month

### Data Transfer
- **Outbound**: First 100GB/month free, then ~$0.09/GB
- **Inbound**: Usually free

### Total Monthly Cost Estimate

#### m7i-flex.large (Recommended)
- Instance: ~$97/month
- Storage (20GB): ~$1.60/month
- **Total**: ~$98.60/month

#### t3.small (Budget Option)
- Instance: ~$15/month
- Storage (20GB): ~$1.60/month
- **Total**: ~$16.60/month

## Cost Optimization Strategies

### 1. Use Free Tier While Available
- ✅ Currently using `m7i-flex.large` - **FREE for 12 months**
- No cost difference between instance types in Free Tier
- Use the best instance type while it's free!

### 2. After Free Tier Expires

**Option A: Keep m7i-flex.large** (Best Performance)
- Cost: ~$98/month
- Pros: Excellent performance, no memory issues
- Cons: Higher cost

**Option B: Downgrade to t3.small** (Cost-Effective)
- Cost: ~$16/month
- Pros: Much cheaper, still adequate for dev
- Cons: Less memory, may need optimization

**Option C: Stop Instance When Not in Use**
- Cost: Only pay for hours used
- Example: 8 hours/day = ~$32/month (m7i-flex.large)
- Use AWS Systems Manager to automate start/stop

### 3. Use Reserved Instances (After Free Tier)
- **1-year Reserved**: ~40% discount
- **3-year Reserved**: ~60% discount
- **Example**: m7i-flex.large 1-year = ~$58/month (vs $97 on-demand)

## Recommendations

### Current (Free Tier Active)
✅ **Keep m7i-flex.large** - It's FREE and gives best performance!

### After Free Tier Expires

**For Development:**
- Use `t3.small` (~$16/month) - Good balance of cost and performance
- Or stop instance when not in use

**For Production:**
- Use `m7i-flex.large` (~$98/month) - Better performance
- Consider Reserved Instances for 40-60% savings

## Cost Monitoring

### Set Up Billing Alerts
```bash
# Create billing alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "MonthlyEC2Cost" \
  --alarm-description "Alert when EC2 costs exceed threshold" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --evaluation-periods 1 \
  --threshold 50 \
  --comparison-operator GreaterThanThreshold
```

### Check Current Costs
- AWS Cost Explorer: https://console.aws.amazon.com/cost-management/home
- AWS Pricing Calculator: https://calculator.aws/

## Summary

**Within Free Tier:**
- ✅ All eligible instances cost **$0.00**
- ✅ Use `m7i-flex.large` - best performance, same cost
- ✅ 750 hours/month = ~31 days continuous

**After Free Tier:**
- `m7i-flex.large`: ~$98/month (24/7)
- `t3.small`: ~$16/month (24/7)
- Consider stopping instance when not in use
- Consider Reserved Instances for long-term savings
