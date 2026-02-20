# Terraform State Lock Error

## What you're seeing

```
Error: Error acquiring the state lock
ConditionalCheckFailedException: The conditional request failed
Lock Info:
  ID:        3b9a0bc3-b8f1-50f3-52f9-53659b56a628
  Path:      shelfshack-terraform-state-v2/shelfshack/dev/terraform.tfstate
  Operation: OperationTypeApply
  Who:       runner@runnervmwffz4
```

This means a **previous Terraform run** (e.g. a cancelled or failed GitHub Actions job) left a lock in DynamoDB. New runs cannot acquire the lock until it is released.

## Fix: release the lock

From the **same backend** (same env and state path), run:

```bash
cd envs/dev   # or envs/prod

terraform force-unlock 3b9a0bc3-b8f1-50f3-52f9-53659b56a628
```

Use the **exact Lock ID** from your error message (the UUID in `Lock Info: ID:`).

- Only run this if you're sure no other Terraform run is in progress.
- After unlocking, re-run your pipeline or `terraform apply`.

## From GitHub Actions (this repo)

1. **Unlock only:** Go to **Actions** → **Unlock Terraform State** → Run workflow. Enter the **Lock ID** from the error (e.g. `3b9a0bc3-b8f1-50f3-52f9-53659b56a628`) and the environment (`dev` / `prod`). Then re-run your Terraform Apply.
2. **Automatic retry:** The **Terraform Apply** workflow runs apply via `scripts/terraform-apply-with-unlock-retry.sh`. If apply fails with "Error acquiring the state lock", the script parses the lock ID, runs `terraform force-unlock`, and retries apply once.

## If Terraform runs in another repo

If your Terraform apply runs from a **different repo** (e.g. backend app repo that checks out this infra repo):

1. **Unlock from this repo:** Push the new workflows to this repo, then in this repo go to **Actions** → **Unlock Terraform State**, run it with the lock ID and environment, then re-run your pipeline in the other repo.
2. **Unlock locally:** From your machine, clone this repo, `cd envs/dev` (or prod), run `terraform init -reconfigure`, then `terraform force-unlock <LOCK_ID>`.

## Avoiding future locks

- Use **one** Terraform apply at a time per environment (e.g. `concurrency` in the workflow).
- Prefer **Deploy only** for routine redeploys so apply is faster and less likely to be cancelled mid-run.
