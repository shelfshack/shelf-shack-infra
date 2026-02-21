# CORS for Production (shelfshack.com)

## Why explicit origins in prod

- **Dev** often works with `allow_origins = ["*"]` because you may not send credentials or use localhost.
- **Prod** with a real domain (e.g. https://shelfshack.com) and **Google sign-in** (or any request with cookies/Authorization) requires the API to respond with the **exact** request origin in `Access-Control-Allow-Origin`, not `*`.
- Browsers block credentialed cross-origin responses when the server returns `Access-Control-Allow-Origin: *`.

So in **prod** we set `http_api_cors_origins` in `envs/prod/terraform.tfvars` to the real frontend origins.

## What was changed

In `envs/prod/terraform.tfvars`:

- **http_api_cors_origins**: `["*"]` → explicit list including `https://shelfshack.com`, `https://www.shelfshack.com`, and localhost for dev.
- **http_api_cors_methods**: Explicit list including `OPTIONS` for preflight.
- **http_api_cors_headers**: Explicit list including `Authorization`, `Content-Type`, etc.

After changing, run:

```bash
cd envs/prod
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Or use the **Terraform Apply** workflow with **deploy_only** so only the API Gateway CORS config is updated.

## If your domain is different

If the production domain is different (e.g. `shellsheck.com` or a custom Amplify URL), add it to `http_api_cors_origins` in `envs/prod/terraform.tfvars`:

```hcl
http_api_cors_origins = [
  "https://shelfshack.com",
  "https://www.shelfshack.com",
  "https://your-actual-domain.com",   # add here
  "http://localhost:3000",
  "http://localhost:5173"
]
```

Use the **exact** scheme and host the browser uses (e.g. `https://www.shelfshack.com` if the user visits with `www`).

## Google OAuth (redirect URIs)

CORS allows the **browser** to call your API from your domain. For **Google sign-in** you also need:

1. **Google Cloud Console** → APIs & Services → Credentials → your OAuth 2.0 Client ID.
2. **Authorized JavaScript origins**: add `https://shelfshack.com` and `https://www.shelfshack.com` (and any custom API domain if the frontend calls it).
3. **Authorized redirect URIs**: add the callback URLs your app uses after Google login (e.g. `https://shelfshack.com/auth/callback` or whatever your app expects).

Without these, Google may block the redirect or token flow even when CORS is correct.

## Backend (Python) CORS

If your **backend** (FastAPI/Flask) also sets CORS headers, keep them in sync:

- Allow the same origins (e.g. `https://shelfshack.com`, `https://www.shelfshack.com`).
- Allow the same methods and headers.

API Gateway handles **OPTIONS** preflight and adds CORS headers to responses when `cors_configuration` is set; the backend can still add headers for non-OPTIONS responses. Either layer can break CORS if it omits or overrides the right origin.
