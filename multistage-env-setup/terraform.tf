terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "6.33.0"
    }
  }

  backend "s3" {
    bucket = "terra-buck-et123"
    key = "terraform.tfstate"
    region = "ap-south-1"
    dynamodb_table = "my-terraform-lock-table"
  }
}
