# Pipeline: Use Deploy-Only (Never Full Apply in CI)

## Why the pipeline was destroying resources

When the pipeline runs **full** `terraform apply` (no `-target=...`):

1. The **networking module** used to set `count = 0` for the VPC when it detected an existing VPC in AWS by name (`create_if_not_exists`).
2. Your **state** still had those resources (created by Terraform earlier).
3. Terraform then **planned to destroy** them because they were no longer in the config.
4. The destroy would run (or fail with `prevent_destroy`) and the pipeline would hang or error.

This is now fixed: networking only uses an existing VPC when you explicitly set **`adopt_vpc_id`** (e.g. for state-loss recovery). By default `adopt_vpc_id` is null, so Terraform always keeps managing the VPC and **full plan no longer tries to destroy it.** You can run full `terraform plan` / `apply` without destroy. For routine CI/CD, still prefer deploy-only so runs stay fast and safe.

## What was changed

### 1. Networking: `prevent_destroy = true`

In **modules/networking/main.tf**, `lifecycle { prevent_destroy = true }` was added to:

- `aws_vpc.this`
- `aws_internet_gateway.this`
- `aws_subnet.public`
- `aws_subnet.private`

So even if someone runs a full apply and the plan includes destroy of these resources, **Terraform will error** and will not destroy them. The pipeline fails with a clear error instead of tearing down infra.

### 2. Main workflow: deploy-only only

**Terraform Apply** (`.github/workflows/terraform-apply.yml`) now **only** runs a **deploy-only** apply. It no longer has a “full apply” option. It always runs:

```bash
terraform apply -auto-approve \
  -target=module.ecs_service \
  -target=module.websocket_lambda \
  -target=aws_apigatewayv2_integration.backend \
  -target=aws_apigatewayv2_integration.backend_root \
  -target=null_resource.amplify_env_vars[0]
```

So from this repo, the main workflow **never** touches VPC, subnets, IGW, RDS, etc. It only updates:

- ECS service / task
- WebSocket Lambda
- API Gateway integrations (backend URL)
- Amplify env vars

### 3. Full apply: separate workflow

**Terraform Full Apply** (`.github/workflows/terraform-full-apply.yml`) is a separate, manual workflow for rare cases when you change infra (new resources, variables, modules). Use it only when you intend to do a full plan/apply. Do **not** use it for routine CI/CD.

## If your pipeline is in another repo

If Terraform runs from a **different** repo (e.g. backend app repo that checks out this infra repo), that pipeline **must** use **deploy-only** for normal runs.

Use this exact pattern (from the env directory, e.g. `envs/dev` or `envs/prod`):

```bash
cd envs/<environment>   # dev or prod
terraform init -reconfigure
terraform apply -auto-approve \
  -target=module.ecs_service \
  -target=module.websocket_lambda \
  -target=aws_apigatewayv2_integration.backend \
  -target=aws_apigatewayv2_integration.backend_root \
  -target=null_resource.amplify_env_vars[0]
```

Optional: use the unlock-retry script from this repo so state lock errors are handled:

```bash
bash scripts/terraform-apply-with-unlock-retry.sh -auto-approve \
  -target=module.ecs_service \
  -target=module.websocket_lambda \
  -target=aws_apigatewayv2_integration.backend \
  -target=aws_apigatewayv2_integration.backend_root \
  -target=null_resource.amplify_env_vars[0]
```

**Do not** run `terraform apply -auto-approve` without `-target=...` in CI. That is a full apply and can plan (and, without `prevent_destroy`, execute) destroy of networking.

## Summary

| Action | Use |
|--------|-----|
| **Terraform Apply** (this repo) | Routine deploys. Deploy-only only. Safe for CI. |
| **Terraform Full Apply** (this repo) | Manual only, when changing infra. |
| **Pipeline in other repo** | Must use the `-target=...` deploy-only command above. Never full apply. |
| **prevent_destroy** in networking | Ensures VPC/IGW/subnets are never destroyed even if a full apply is run. |
