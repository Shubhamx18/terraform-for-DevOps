resource "aws_dynamodb_table" "basic_dynamo_db" {   
  name         = "my-terraform-lock-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    name = "my_db"
  }
}
