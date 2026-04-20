# Backend Configuration Reference

Each stack uses an S3 backend with DynamoDB state locking.

## Backend Structure

```
Bucket: serenity-{env}-terraform-v2-state-{account_id}
Key:    {env}/{stack}/terraform.tfstate
Region: eu-central-1
Table:  serenity-{env}-terraform-v2-locks
Encrypt: true
```

## Per-Stack State Files

| Stack | State Key |
|-------|-----------|
| 01-networking | `dev/networking/terraform.tfstate` |
| 02-eks | `dev/eks/terraform.tfstate` |
| 03-databases | `dev/databases/terraform.tfstate` |

## Locking

DynamoDB table uses `LockID` as the hash key. Terraform automatically acquires and releases locks during `plan` and `apply`.

## Encryption

- State files: SSE-KMS (dedicated KMS key in bootstrap)
- In transit: TLS via `encrypt = true`

## Partial Configuration

The backend is fully configured in each stack's `backend.tf`. No `-backend-config` flags are required for `terraform init`.
