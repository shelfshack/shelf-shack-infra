# Final Fix: Use Specific OpenSearch Version

## Problem
Using `latest` tag pulls OpenSearch 3.x which:
- Requires more resources
- Has stricter requirements
- May fail on t3.micro instances

## Solution: Pin to Stable Version

Add these to `terraform.tfvars`:

```hcl
opensearch_ec2_image   = "opensearchproject/opensearch"
opensearch_ec2_version = "2.11.0"  # Stable, tested version
opensearch_ec2_java_heap_size = "256m"  # Smaller for t3.micro
```

## Steps

### 1. Update terraform.tfvars
```bash
cd envs/dev
cat >> terraform.tfvars << 'EOF'

# OpenSearch EC2 Configuration - Use stable version
opensearch_ec2_image   = "opensearchproject/opensearch"
opensearch_ec2_version = "2.11.0"
opensearch_ec2_java_heap_size = "256m"
EOF
```

### 2. Recreate Instance
```bash
terraform taint module.opensearch_ec2[0].aws_instance.opensearch
terraform apply -var-file=terraform.tfvars
```

### 3. Wait and Verify
Wait 5-8 minutes, then:
```bash
./diagnose_opensearch_complete.sh
```

## Why This Should Work

- **2.11.0** is stable and well-tested
- **256m heap** fits better in t3.micro (1GB RAM)
- **Specific version** avoids latest tag surprises
- **Same fixes** (password, network binding) still apply

## If Still Not Working

Check EC2 Console:
1. Go to EC2 → Instances
2. Select instance: i-0128eeadc627beac0
3. Actions → Monitor and troubleshoot → Get system log
4. Look for user_data execution errors

Or try Session Manager:
1. EC2 Console → Connect → Session Manager
2. Run: `sudo tail -100 /var/log/user-data.log`
3. Check what failed
