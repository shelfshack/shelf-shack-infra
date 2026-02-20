# GitHub Actions – Terraform

## Workflows

| Workflow | Purpose |
|----------|--------|
| **Terraform Apply** | Plan and apply Terraform (full or deploy-only). Handles stale state lock by unlocking and retrying once. |
| **Unlock Terraform State** | One-off: release a stale state lock when a previous run was cancelled or failed. |

## Terraform Apply (recommended for redeploys)

- **Trigger:** Actions → Terraform Apply → Run workflow.
- **Inputs:**
  - **environment:** `dev` or `prod`.
  - **deploy_only:** `true` (default) or `false`.

### Deploy only (default: `true`)

Use this for **routine redeploys**. Only these are updated:

- **ECS service / task** (new task definition, new deployment).
- **WebSocket Lambda** (code and env vars).
- **HTTP API Gateway** integration URIs (backend URL).
- **Amplify branch** environment variables (API URLs for the frontend).

No changes to VPC, RDS, OpenSearch, security groups, or other infra. This avoids accidental destroys and keeps runs short.

### Full apply (`deploy_only: false`)

Use when you changed Terraform under `envs/*` (e.g. new resources, variables, or modules). Runs a normal `terraform plan` and `terraform apply` for that environment.

### State lock handling

If apply fails with **Error acquiring the state lock**, the apply step runs `scripts/terraform-apply-with-unlock-retry.sh`, which:

1. Parses the lock ID from the error.
2. Runs `terraform force-unlock <id>`.
3. Retries `terraform apply` once.

So you usually don’t need to run **Unlock Terraform State** unless you want to unlock without re-running apply.

## Unlock Terraform State

Use when a run left a lock (e.g. job cancelled) and you don’t want to run a full apply yet.

1. Actions → Unlock Terraform State → Run workflow.
2. Choose **environment** (`dev` or `prod`).
3. Paste the **Lock ID** from the error (e.g. `3b9a0bc3-b8f1-50f3-52f9-53659b56a628`).
4. Run the workflow, then re-run your Terraform Apply (or your pipeline in another repo).

## Required secrets

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

(Or switch to OIDC with `aws-actions/configure-aws-credentials`.)

## If your pipeline is in another repo

If Terraform is run from a **different** repo (e.g. backend repo that checks out this infra repo):

1. **Unlock:** In **this** repo, run **Unlock Terraform State** with the lock ID, then re-run the pipeline in the other repo.
2. **Deploy-only behavior:** In the other repo, run Terraform with the same targets when you only want to redeploy app/config:
   ```bash
   terraform apply -auto-approve \
     -target=module.ecs_service \
     -target=module.websocket_lambda \
     -target=aws_apigatewayv2_integration.backend \
     -target=aws_apigatewayv2_integration.backend_root \
     -target=null_resource.amplify_env_vars[0]
   ```
   Optionally use `scripts/terraform-apply-with-unlock-retry.sh` from this repo so lock errors are handled the same way.
