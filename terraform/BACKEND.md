# Backend Configuration Reference

Each stack uses an S3 backend with DynamoDB state locking.

## Backend Structure

```
Bucket: serenity-{env}-terraform-state-{account_id}
Key:    {env}/{stack}/terraform.tfstate
Region: eu-central-1
Table:  serenity-{env}-terraform-locks
Encrypt: true
```

## Per-Stack State Files

| Stack | State Key |
|-------|-----------|
| shared/networking | `shared/networking/terraform.tfstate` |
| shared/eks | `shared/eks/terraform.tfstate` |
| dev/aurora | `dev/aurora/terraform.tfstate` |
| dev/redis | `dev/redis/terraform.tfstate` |
| prod/aurora | `prod/aurora/terraform.tfstate` |
| prod/redis | `prod/redis/terraform.tfstate` |

## Locking

DynamoDB table uses `LockID` as the hash key. Terraform automatically acquires and releases locks during `plan` and `apply`.

## Encryption

- State files: SSE-KMS (dedicated KMS key in bootstrap)
- In transit: TLS via `encrypt = true`

## Partial Configuration

The backend is fully configured in each stack's `backend.tf`. No `-backend-config` flags are required for `terraform init`.
