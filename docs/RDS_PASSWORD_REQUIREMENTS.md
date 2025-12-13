# RDS PostgreSQL Password Requirements

## AWS Requirements

AWS RDS PostgreSQL has strict password requirements:

1. **Length**: 8-128 characters
2. **Character Types**: Must contain at least 3 of the following:
   - Uppercase letters (A-Z)
   - Lowercase letters (a-z)
   - Numbers (0-9)
   - Special characters (!@#$%^&*()_+-=[]{}|;:,.<>?)

## Common Issues

### Error: "Invalid master password"

This error occurs when the password doesn't meet AWS requirements.

**Example of invalid password**: `RohitSajud1234`
- ✅ Has uppercase (R, S)
- ✅ Has lowercase (ohit, ajud)
- ✅ Has numbers (1234)
- ❌ Missing special character

**Solution**: Add a special character:
- `RohitSajud1234!`
- `RohitSajud1234@`
- `RohitSajud1234#`

## Setting the Password

### Method 1: Environment Variable (Recommended)

```bash
# Set the password as an environment variable
export TF_VAR_db_master_password='RohitSajud1234!'

# Or use uppercase-friendly version
export TF_VAR_DB_MASTER_PASSWORD='RohitSajud1234!'

# Then run terraform
cd envs/dev
terraform apply
```

### Method 2: Terraform Variables File (Not Recommended for Production)

Add to `envs/dev/terraform.tfvars`:

```hcl
db_master_password = "RohitSajud1234!"
```

**Warning**: This file should NOT be committed to version control if it contains passwords.

### Method 3: AWS Secrets Manager (Most Secure)

1. Create a secret in AWS Secrets Manager:
   ```bash
   aws secretsmanager create-secret \
     --name rentify-dev/rds-password \
     --secret-string '{"password":"RohitSajud1234!"}'
   ```

2. Get the secret ARN and add to `terraform.tfvars`:
   ```hcl
   db_master_password_secret_arn = "arn:aws:secretsmanager:us-east-1:ACCOUNT:secret:rentify-dev/rds-password-XXXXX"
   ```

## Password Examples

### Valid Passwords:
- `MyPass123!` (has uppercase, lowercase, numbers, special)
- `SecureP@ssw0rd` (has uppercase, lowercase, numbers, special)
- `Test1234#` (has uppercase, lowercase, numbers, special)
- `RohitSajud1234!` (has uppercase, lowercase, numbers, special)

### Invalid Passwords:
- `password123` (missing uppercase and special)
- `PASSWORD123` (missing lowercase and special)
- `RohitSajud1234` (missing special character)
- `Pass!` (too short, less than 8 characters)

## Verification

After setting the password, verify it meets requirements:

```bash
# Check password length (should be 8-128)
echo -n "RohitSajud1234!" | wc -c

# Verify it has required character types
# (Manual check: uppercase, lowercase, numbers, special)
```

## Troubleshooting

### Password Still Not Working

1. **Check for hidden characters**: Copy/paste might introduce hidden characters
2. **Check quotes**: Ensure proper quoting in shell/Terraform
3. **Check encoding**: Some special characters might not be valid
4. **Try a simpler password**: Test with `Test1234!` to verify setup

### Password in Terraform State

⚠️ **Security Note**: Terraform stores the password in state files. Ensure:
- State files are encrypted (S3 backend with encryption)
- State files are not committed to version control
- Access to state files is restricted

### Changing Password After Creation

To change the password of an existing RDS instance:

1. Update the password in your configuration
2. Set `apply_immediately = true` in RDS module
3. Run `terraform apply`

The password change will trigger an RDS instance modification.

