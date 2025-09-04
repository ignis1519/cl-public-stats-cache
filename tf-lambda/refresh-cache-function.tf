# --- Data Source to Zip the Python File ---
data "archive_file" "lambda_zip-refresh-cache" {
  type        = "zip"
  source_dir  = "./src/refresh-cache"
  output_path = "tmp.lambda_function.zip"
}

# --- IAM Role for Lambda ---
resource "aws_iam_role" "lambda-refresh-cache_exec_role" {
  name = "lambda-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

# Attach a policy to the role allowing it to write to DynamoDB, CloudWatch Logs, and read from SSM.
resource "aws_iam_role_policy" "lambda-refresh-cache-policy" {
  name = "lambda-refresh-cache-policy"
  role = aws_iam_role.lambda-refresh-cache_exec_role.id # Ensure this role name is correct

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # 1. For CloudWatch Logs
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      # 2. For DynamoDB Access
      {
        Effect   = "Allow"
        Action   = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.public_stats_table.arn
      },
      # 3. For SSM Parameter Store
      {
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = [
          "arn:aws:ssm:*:*:parameter/bcch/username",
          "arn:aws:ssm:*:*:parameter/bcch/password"
        ]
      },
      # 4. For KMS Decryption
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = "arn:aws:kms:*:*:alias/aws/ssm" # Default AWS-managed key for SSM
      }
    ]
  })
}

# --- Lambda Function ---
resource "aws_lambda_function" "refresh-cache" {
  filename         = data.archive_file.lambda_zip-refresh-cache.output_path
  function_name    = "refresh-cache"
  role             = aws_iam_role.lambda-refresh-cache_exec_role.arn
  handler          = "refresh-cache.handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_zip-refresh-cache.output_base64sha256
  timeout          = 300
}

# --- CloudWatch Event Rule (The Scheduler) ---
resource "aws_cloudwatch_event_rule" "schedule-refresh-cache" {
  name                = "schedule-refresh-cache-rule"
  schedule_expression = "cron(0 12 * * ? *)"
}

# --- CloudWatch Event Target ---
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.schedule-refresh-cache.name
  target_id = "refresh_cache_function_target"
  arn       = aws_lambda_function.refresh-cache.arn
}

# --- Lambda Permission ---
resource "aws_lambda_permission" "allow_cloudwatch_to_call_lambda-refresh-cache" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.refresh-cache.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule-refresh-cache.arn
}