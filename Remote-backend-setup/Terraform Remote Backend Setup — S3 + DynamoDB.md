# Terraform Remote Backend Setup — S3 + DynamoDB

---

## Why Remote Backend?

| Problem (Local State) | Solution (Remote Backend) |
|-----------------------|--------------------------|
| State only on your machine | Stored in S3 — accessible by team |
| No locking — concurrent apply corrupts state | DynamoDB locks state during apply |
| No backup | S3 versioning keeps every version |
| State file is plain text locally | S3 encryption secures it |

---

## Flow — Two Step Process

> **Important:** You cannot create S3 + DynamoDB and use them as backend in the same apply.
> Backend must exist before Terraform can use it.

```
Step 1 → Apply infra.tf       → Creates S3 bucket + DynamoDB table
Step 2 → Add backend.tf       → terraform init → state migrates to S3
```

---

## Step 1 — Create S3 + DynamoDB via Terraform

**`provider.tf`**

```hcl
provider "aws" {
  region = "ap-south-1"
}

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

**`infra.tf`**

```hcl
# S3 Bucket — stores state files
resource "aws_s3_bucket" "tf_state" {
  bucket = "terra-buck-et123"

  tags = {
    Name        = "Terraform State Bucket"
    Environment = "Dev"
  }
}

# Versioning — allows state rollback
resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption — state stored securely at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access — no accidental exposure
resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB — state locking
resource "aws_dynamodb_table" "tf_lock" {
  name         = "my-terraform-lock-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "Terraform Lock Table"
  }
}
```

Apply:

```bash
terraform init
terraform apply
```

> At this point state is still **local**. S3 + DynamoDB now exist in AWS.

---

## Step 2 — Add Backend Config

Create a new file **`backend.tf`** in the same project:

```hcl
terraform {
  backend "s3" {
    bucket         = "terra-buck-et123"
    key            = "terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "my-terraform-lock-table"
    encrypt        = true
  }
}
```

Re-initialize:

```bash
terraform init
```

Terraform will prompt:

```
Do you want to copy existing state to the new backend?
Enter a value: yes
```

> State is now migrated from local to S3. Local `terraform.tfstate` is no longer used.

---

## Step 3 — Integrate with Multi-Workspace Setup

No changes needed to `backend.tf`. Terraform automatically creates separate state paths per workspace.

```bash
terraform workspace select default → uses → terraform.tfstate
terraform workspace select dev     → uses → env/dev/terraform.tfstate
terraform workspace select prod    → uses → env/prod/terraform.tfstate
```

S3 bucket structure after applying all workspaces:

```
terra-buck-et123/
├── terraform.tfstate
└── env/
    ├── dev/
    │   └── terraform.tfstate
    └── prod/
        └── terraform.tfstate
```

One `backend.tf` — works for all workspaces automatically.

---

## How Locking Works

```
Dev 1 runs terraform apply
  → Terraform writes LockID to DynamoDB
  → Apply runs

Dev 2 runs terraform apply at same time
  → Terraform checks DynamoDB → Lock exists
  → Returns error: state is locked

Dev 1 apply finishes
  → Lock released from DynamoDB
  → Dev 2 can now apply
```

If apply crashes and lock is stuck:

```bash
terraform force-unlock <lock-id>
```

---

## What Each Resource Does

| Resource | Purpose |
|----------|---------|
| `aws_s3_bucket` | Stores `.tfstate` files |
| `aws_s3_bucket_versioning` | Keeps history of every state — enables rollback |
| `aws_s3_bucket_server_side_encryption_configuration` | Encrypts state at rest using AES256 |
| `aws_s3_bucket_public_access_block` | Blocks any public access to state files |
| `aws_dynamodb_table` | Locks state during apply to prevent conflicts |

---

## State Rollback (If Something Breaks)

Because versioning is enabled on S3, every `apply` saves a new version.

```bash
# List all versions of prod state
aws s3api list-object-versions \
  --bucket terra-buck-et123 \
  --prefix env/prod/terraform.tfstate

# Restore a previous version
aws s3api copy-object \
  --bucket terra-buck-et123 \
  --copy-source "terra-buck-et123/env/prod/terraform.tfstate?versionId=<version-id>" \
  --key env/prod/terraform.tfstate
```

---

## Useful State Commands

```bash
# List all resources tracked in state
terraform state list

# Inspect a specific resource in state
terraform state show aws_instance.my_ec2

# Pull remote state to local (read only)
terraform state pull

# Remove resource from state without destroying it in AWS
terraform state rm aws_instance.my_ec2
```

---

## Complete Setup Checklist

- [ ] `provider.tf` — AWS provider with version `~> 5.0`
- [ ] `infra.tf` — S3 bucket with versioning + encryption + public access block
- [ ] `infra.tf` — DynamoDB table with `LockID` partition key
- [ ] `terraform init && terraform apply` — creates S3 + DynamoDB in AWS
- [ ] `backend.tf` — backend config pointing to S3 + DynamoDB
- [ ] `terraform init` again — migrates local state to S3
- [ ] Workspaces applied — separate state per env in S3

---

## Summary

```
S3 Bucket        → stores state
DynamoDB Table   → locks state during apply
Versioning       → rollback if state breaks
Encryption       → secures state at rest
Public Block     → no accidental exposure
Workspace        → auto-creates separate path in S3
```
