# This file provisions the S3 bucket and DynamoDB table
# required for Terraform to manage its state remotely.
# Run this file once before your main Terraform project.

# Define the AWS provider
provider "aws" {
  region = "us-east-1"
}
