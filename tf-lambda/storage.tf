# --- DynamoDB Table (Managed by Terraform) ---
# Note: This is the table for the application, not the state lock.
resource "aws_dynamodb_table" "public_stats_table" {
  name           = "public-stats"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "statistic"
  range_key      = "date"

  attribute {
    name = "statistic"
    type = "S"
  }

  attribute {
    name = "date"
    type = "S"
  }
}
