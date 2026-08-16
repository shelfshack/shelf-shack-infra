# Phase 1 secrets — required before deploying the backend

The backend now refuses to start when these are missing. Terraform only
*references* keys inside the existing Secrets Manager secrets; the key/value
pairs themselves must be added in AWS first, or the ECS task will fail to pull
its secrets and the service will not come up.

Do these steps **before** merging and deploying the backend change.

| Variable | dev | prod | Where it lives |
|---|---|---|---|
| `SECRET_KEY` | required | required | `app_secrets` → Secrets Manager |
| `CHAT_ENCRYPTION_KEY` | not enforced | required | `app_secrets` → Secrets Manager |
| `CORS_ALLOW_ORIGINS` | not enforced | required | `app_environment` (plain, not secret) |

Secret names:
- dev — `dev/shelfshack/backend_secrets` (`-X5iN9N`)
- prod — `prod/shelfshack/backend_secrets` (`-XwsTaO`)

## 1. Generate the values

```bash
# JWT signing key (min 32 chars enforced at startup)
python3 -c "import secrets; print(secrets.token_urlsafe(48))"

# Fernet key for chat ciphertext — must be exactly this format
python3 -c "import base64, os; print(base64.urlsafe_b64encode(os.urandom(32)).decode())"
```

Use **different** values per environment.

## 2. Add them to Secrets Manager

Both secrets are JSON blobs; add the keys without disturbing existing ones.

```bash
# prod
aws secretsmanager get-secret-value \
  --secret-id prod/shelfshack/backend_secrets \
  --query SecretString --output text > /tmp/prod.json

# edit /tmp/prod.json, adding:
#   "SECRET_KEY": "<generated>",
#   "CHAT_ENCRYPTION_KEY": "<generated>"

aws secretsmanager put-secret-value \
  --secret-id prod/shelfshack/backend_secrets \
  --secret-string file:///tmp/prod.json

rm /tmp/prod.json
```

Repeat for `dev/shelfshack/backend_secrets` with `SECRET_KEY` only.

## 3. Apply and deploy

Apply Terraform first so the task definition includes the new secrets, then
deploy the backend image. Deploying the backend before the task definition is
updated will leave the service crash-looping on a `ConfigError`.

## Consequences to expect

**Every session is invalidated.** Existing JWTs were signed with whatever key
production was using; issuing a new one logs everybody out. Expect a spike in
logins and a drop in active sessions right after the deploy.

**Chat history predating this change becomes unreadable.** Ciphertext was
encrypted with a key derived from `SECRET_KEY`. Once `CHAT_ENCRYPTION_KEY` is
set, old messages will not decrypt and the API returns an error for them.

If production holds chat history worth keeping, decrypt and re-encrypt it before
deploying rather than after — the old key is `SHA256(old SECRET_KEY)`,
base64-urlsafe encoded, and is unrecoverable once the old value is discarded.

## Verifying

```bash
# task definition should list both secrets
aws ecs describe-task-definition \
  --task-definition shelfshack-prod \
  --query 'taskDefinition.containerDefinitions[0].secrets[].name'

# an attacker-controlled origin must NOT be reflected back
curl -sI -H "Origin: https://anything.amplifyapp.com" \
  https://<api-host>/api/categories | grep -i access-control-allow-origin

# the real frontend origin must be
curl -sI -H "Origin: https://shelfshack.com" \
  https://<api-host>/api/categories | grep -i access-control-allow-origin
```
