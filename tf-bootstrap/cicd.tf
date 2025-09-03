# -----------------------------------------------------------------------------
# AWS CodeStar Connection to GitHub (Provisioned by this configuration)
# This resource will create the connection. You must complete the one-time
# manual authorization handshake in the AWS Console after it's created.
# -----------------------------------------------------------------------------
resource "aws_codestarconnections_connection" "github_connection" {
  name          = "gh-conn-cl-unemployment"
  provider_type = "GitHub"
}


# -----------------------------------------------------------------------------
# S3 Bucket for CodePipeline Artifacts
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "codepipeline_artifacts" {
  bucket = "asr-codepipeline-artifacts" # Bucket names must be globally unique
}

# -----------------------------------------------------------------------------
# IAM Role and Policy for the CodeBuild Project
# -----------------------------------------------------------------------------
resource "aws_iam_role" "codebuild_role" {
  name = "CodeBuild-Terraform-Lambda-Deploy-Role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "codebuild_policy" {
  name   = "CodeBuild-Terraform-Lambda-Deploy-Policy"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      # Standard permissions for CodeBuild to log and manage builds
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = ["arn:aws:logs:*:*:*"]
      },
      # Permissions to access the Lambda's Terraform state
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.terraform_state_bucket.arn,
          "${aws_s3_bucket.terraform_state_bucket.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.terraform_state_lock.arn
      },
      # Permissions for Terraform to provision the Lambda and its dependencies
      {
        Effect   = "Allow"
        Action   = [
          "lambda:*", "iam:PassRole", "iam:CreateRole", "iam:AttachRolePolicy",
          "iam:PutRolePolicy", "dynamodb:*", "ssm:*", "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_policy_attach" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = aws_iam_policy.codebuild_policy.arn
}


# -----------------------------------------------------------------------------
# IAM Role and Policy for the CodePipeline Service
# -----------------------------------------------------------------------------
resource "aws_iam_role" "codepipeline_role" {
  name = "CodePipeline-Cl-Unemployment-Role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "codepipeline.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "codepipeline_policy" {
  name   = "CodePipeline-Cl-Unemployment-Policy"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      # Permission to manage artifacts in the S3 bucket
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:GetBucketAcl", "s3:GetBucketLocation"]
        Resource = [
          aws_s3_bucket.codepipeline_artifacts.arn,
          "${aws_s3_bucket.codepipeline_artifacts.arn}/*"
        ]
      },
      # UPDATED: Permissions to use the CodeStar Connection and start CodeBuild
      {
        Effect   = "Allow"
        Action   = [
          "codestar-connections:UseConnection",
          "codebuild:StartBuild",
          "codebuild:BatchGetBuilds"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_policy_attach" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = aws_iam_policy.codepipeline_policy.arn
}


# -----------------------------------------------------------------------------
# AWS CodeBuild Project (Refactored for CodePipeline)
# -----------------------------------------------------------------------------
resource "aws_codebuild_project" "cl_unemployment_build" {
  name          = "cl-unemployment-stats-cache-deploy"
  description   = "Builds and deploys the Lambda for cl-unemployment-stats. Triggered by CodePipeline."
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
}

# -----------------------------------------------------------------------------
# AWS CodePipeline Definition
# -----------------------------------------------------------------------------
resource "aws_codepipeline" "cl_unemployment_pipeline" {
  name     = "cl-unemployment-deploy-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_artifacts.bucket
    type     = "S3"
  }

  # --- STAGE 1: Source from GitHub using CodeStar Connection (V2) ---
  stage {
    name = "Source"
    action {
      name             = "SourceGitHub"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceOutput"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github_connection.arn
        FullRepositoryId = "ignis1519/cl-unemployment-stats-cache"
        BranchName       = "main"
      }
    }
  }

  # --- STAGE 2: Build and Deploy with CodeBuild ---
  stage {
    name = "BuildAndDeploy"
    action {
      name            = "TerraformApply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceOutput"]

      configuration = {
        ProjectName = aws_codebuild_project.cl_unemployment_build.name
      }
    }
  }
}

