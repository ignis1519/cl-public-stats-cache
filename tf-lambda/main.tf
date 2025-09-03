# Configure the Terraform backend for S3 state storage.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "asr-terraform"
    key            = "bcch-poc/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "asr-lock-table"
  }
}

# Define the AWS provider
provider "aws" {
  region = "us-east-1"
}