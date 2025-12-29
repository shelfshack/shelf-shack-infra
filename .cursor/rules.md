# Cursor AI Rules — Terraform (Production)

## Core Infrastructure Principles
- Treat all infrastructure as production unless explicitly marked otherwise
- Prefer safety, determinism, and clarity over clever abstractions
- Never introduce changes that cause destructive actions without explicit instruction
- Assume infrastructure changes can impact uptime, data, and security

## Terraform Standards
- Use Terraform >= 1.x features only
- Always use `required_providers` with explicit version constraints
- Avoid deprecated syntax and providers
- Prefer `for_each` over `count` when managing named resources
- Do not rely on implicit dependencies

## State & Environments
- Never assume local state for production
- Use remote backends (S3 + DynamoDB, Terraform Cloud, etc.)
- Do not modify backend configuration without explicit instruction
- Keep environment separation strict (dev, stage, prod)

## Naming & Structure
- Resource names must be deterministic and environment-aware
- Avoid random names unless explicitly required
- Follow a consistent naming convention across all resources
- Do not hardcode environment-specific values

## Modules
- Prefer reusable modules with clear inputs/outputs
- Do not modify a module interface without explaining downstream impact
- Avoid deeply nested modules
- Keep modules opinionated but composable

## Variables & Outputs
- All variables must include:
  - type
  - description
  - sensible defaults (or explicitly required)
- Mark sensitive variables appropriately
- Outputs must be minimal and intentional

## Security & IAM
- Apply least-privilege principles by default
- Never use wildcard IAM permissions unless explicitly required
- Avoid inline IAM policies for complex permissions
- Never expose secrets in code, variables, or outputs

## Networking
- Avoid overlapping CIDR blocks
- Be explicit with ingress/egress rules
- Do not open public access unless explicitly requested
- Prefer private networking by default

## Destructive Operations
- Never remove resources, state, or data stores without confirmation
- Use `prevent_destroy` for critical resources when appropriate
- Highlight any change that may recreate or destroy resources

## Planning & Safety
- Always reason about the Terraform plan before suggesting changes
- Call out potential downtime, replacement, or data loss
- Prefer additive changes over in-place replacements
- Avoid changes that trigger full resource recreation unless unavoidable

## Code Changes
- Explain *why* a change is needed, not just *what* changed
- Identify blast radius for every infrastructure change
- Ask before refactoring shared or critical modules
- Do not auto-format code in a way that obscures diffs

## Cloud-Specific Guardrails
- Assume AWS/GCP/Azure best practices unless told otherwise
- Prefer managed services over self-managed where appropriate
- Avoid experimental or beta features for production systems

## Documentation
- Keep comments meaningful and minimal
- Document non-obvious decisions and trade-offs
- Assume future operators are not the original authors
