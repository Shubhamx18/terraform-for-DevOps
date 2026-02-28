# Terraform Multi-Workspace Setup Manual

> **Goal:** Manage Dev, Prod environments using one codebase, workspaces, and S3 remote state.

---

## Prerequisites

- Terraform installed
- AWS CLI configured (`aws configure`)
- S3 bucket created for remote state (e.g., `terra-buck-et123`)
- DynamoDB table created for state locking (e.g., `my-terraform-lock-table`)
- SSH key pair generated locally (`terra_key_ec2.pub`)

---

## Project Structure

```
project/
├── backend.tf
├── provider.tf
├── variables.tf
├── ec2.tf
├── output.tf
├── docker_install.sh
└── terra_key_ec2.pub
```

---

## Step 1 — Configure Remote Backend

**`backend.tf`**

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.33.0"
    }
  }

  backend "s3" {
    bucket         = "terra-buck-et123"
    key            = "terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "my-terraform-lock-table"
  }
}
```

**`provider.tf`**

```hcl
provider "aws" {
  region = "ap-south-1"
}
```

---

## Step 2 — Define Variables

**`variables.tf`**

```hcl
variable "ec2_ami" {
  default = "ami-0f5ee92e2d63afc18"
  type    = string
}

# Workspace-based instance type list
# Each workspace maps to a list of instance types
variable "instance_type" {
  default = {
    default = ["t3.micro"]
    dev     = ["t3.micro", "t3.small", "t3.micro"]
    prod    = ["t3.micro", "c7i-flex.large"]
  }
}
```

> **Why a list?** Each workspace can create multiple EC2 instances with different types.
> `default` = 1 instance, `dev` = 3 instances, `prod` = 2 instances.

---

## Step 3 — Create EC2 Resources

**`ec2.tf`**

```hcl
# Key Pair — workspace-specific name to avoid conflicts
resource "aws_key_pair" "mykey" {
  key_name   = "terra-key-ec2-${terraform.workspace}"
  public_key = file("terra_key_ec2.pub")
}

# Use default VPC
resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

# Security Group
resource "aws_default_security_group" "default" {
  vpc_id = aws_default_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "App Port"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }
}

# EC2 Instances — dynamically created per workspace
resource "aws_instance" "my_ec2" {

  depends_on = [aws_default_security_group.default, aws_default_vpc.default]

  # Convert list to indexed map to preserve duplicates (toset() removes them)
  for_each = {
    for idx, val in var.instance_type[terraform.workspace] :
    idx => val
  }

  ami                    = var.ec2_ami
  instance_type          = each.value
  key_name               = aws_key_pair.mykey.key_name
  vpc_security_group_ids = [aws_default_security_group.default.id]
  user_data              = file("docker_install.sh")

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
  }

  tags = {
    Name = "${terraform.workspace}-instance-${each.key}"
  }
}
```

> **Why `for idx, val in list : idx => val` instead of `toset()`?**
> `toset()` removes duplicates. If dev has 3x `t3.micro`, `toset()` collapses them into 1.
> Indexed map preserves all entries using their index (0, 1, 2) as unique keys.

---

## Step 4 — Outputs

**`output.tf`**

```hcl
output "ec2_public_ip" {
  value = [for instance in aws_instance.my_ec2 : instance.public_ip]
}

output "ec2_public_dns" {
  value = [for instance in aws_instance.my_ec2 : instance.public_dns]
}

output "ec2_private_ip" {
  value = [for instance in aws_instance.my_ec2 : instance.private_ip]
}
```

---

## Step 5 — Initialize Terraform

```bash
terraform init
```

Check current workspace:

```bash
terraform workspace list
# * default
```

---

## Step 6 — Create Workspaces

```bash
terraform workspace new dev
terraform workspace new prod
```

Verify all workspaces:

```bash
terraform workspace list
# * default
#   dev
#   prod
```

---

## Step 7 — Deploy Per Workspace

### Default

```bash
terraform workspace select default
terraform apply
```

Creates: `default-instance-0` → `t3.micro`

---

### Dev

```bash
terraform workspace select dev
terraform apply
```

Creates:
- `dev-instance-0` → `t3.micro`
- `dev-instance-1` → `t3.small`
- `dev-instance-2` → `t3.micro`

---

### Prod

```bash
terraform workspace select prod
terraform apply
```

Creates:
- `prod-instance-0` → `t3.micro`
- `prod-instance-1` → `c7i-flex.large`

---

## Step 8 — Verify S3 State Files

After applying in all workspaces, your S3 bucket will contain:

```
terraform.tfstate              → default workspace
env/dev/terraform.tfstate      → dev workspace
env/prod/terraform.tfstate     → prod workspace
```

Each workspace has **isolated state** — no overlap, no overwrite.

---

## Step 9 — Git Setup

```bash
git init
git add .
git commit -m "Terraform multi-workspace setup"
git remote add origin <your-repo-url>
git push -u origin main
```

### Branch to Workspace Convention

| Git Branch | Workspace |
|------------|-----------|
| `main`     | `prod`    |
| `develop`  | `dev`     |

When switching branches, always select the matching workspace before running `apply`.

---

## Common Commands Reference

```bash
# List all workspaces
terraform workspace list

# Show current workspace
terraform workspace show

# Switch workspace
terraform workspace select dev

# Create new workspace
terraform workspace new staging

# Delete workspace (must destroy infra first)
terraform workspace select dev
terraform destroy
terraform workspace select default
terraform workspace delete dev

# Plan without applying
terraform plan

# Apply changes
terraform apply

# Destroy all infra in current workspace
terraform destroy
```

---

## Key Concepts Summary

| Concept | Explanation |
|---------|-------------|
| `terraform.workspace` | Returns current workspace name (e.g., `dev`, `prod`) |
| `variable "env"` | Just a normal variable — does NOT change workspace |
| `for_each` with indexed map | Preserves duplicate instance types in a list |
| `toset()` | Removes duplicates — avoid when list has same values |
| S3 backend key | Terraform auto-prefixes workspace: `env/<ws>/terraform.tfstate` |
| Key pair naming | Must be workspace-specific to avoid AWS duplicate errors |

---

## Important Rules

1. **Workspace ≠ Variable** — `variable "env" = "dev"` does not select dev workspace. Use `terraform workspace select dev`.

2. **Key pairs are global** — AWS key pairs are account-level, not workspace-isolated. Always suffix with `${terraform.workspace}`.

3. **S3 state is auto-isolated** — Set `key = "terraform.tfstate"` in backend; Terraform handles the `env/<workspace>/` prefix automatically.

4. **Never use `toset()` with duplicate types** — Use indexed `for` expression instead.

5. **Apply creates state, not workspace creation** — S3 state file appears only after `terraform apply`, not after `terraform workspace new`.

---

## Workspace-wise Infrastructure Summary

| Workspace | Instances | Types |
|-----------|-----------|-------|
| default | 1 | t3.micro |
| dev | 3 | t3.micro + t3.small + t3.micro |
| prod | 2 | t3.micro + c7i-flex.large |

> Same code. Different infra. Isolated state. One AWS account.
