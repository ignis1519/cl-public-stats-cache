# --- DynamoDB Table (Managed by Terraform) ---
# Note: This is the table for the application, not the state lock.
resource "aws_dynamodb_table" "unemployment_storage_table" {
  name           = "unemployment-storage"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
}
