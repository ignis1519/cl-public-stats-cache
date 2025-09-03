# --- S3 Bucket for Terraform State ---
# This bucket will store your Terraform state file.
# It is configured with versioning to prevent data loss.
resource "aws_s3_bucket" "terraform_state_bucket" {
  bucket = "asr-terraform"

  tags = {
    Name = "Terraform Bucket"
  }
}

# Enable versioning on the S3 bucket
resource "aws_s3_bucket_versioning" "terraform_state_bucket_versioning" {
  bucket = aws_s3_bucket.terraform_state_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# --- DynamoDB Table for State Locking ---
# This table is used by Terraform to lock the state file,
# preventing concurrent runs from corrupting the state.
# The primary key must be "LockID".
resource "aws_dynamodb_table" "terraform_state_lock" {
  name         = "asr-lock-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
