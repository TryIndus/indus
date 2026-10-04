mock_provider "aws" {
  override_during = plan
  mock_data "aws_availability_zones" { defaults = { names = ["us-east-1a", "us-east-1b"] } }
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_caller_identity" { defaults = { account_id = "111111111111" } }
  mock_data "aws_ssm_parameter" { defaults = { value = "ami-test" } }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"ec2.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}"
    }
  }
}

variables {
  account_id            = "111111111111"
  vpc_cidr              = "10.52.0.0/16"
  preview_domain_name   = "optimized.indus.example.com"
  cognito_callback_urls = ["https://optimized.indus.example.com/auth/callback"]
  cognito_logout_urls   = ["https://optimized.indus.example.com/auth"]
  ecr_repository_arns = {
    platform-api = "arn:aws:ecr:us-east-1:111111111111:repository/indus-optimized/platform-api"
  }
}

run "single_host_cost_profile" {
  command = plan
  assert {
    condition     = aws_db_instance.this.multi_az == false
    error_message = "Optimized RDS must remain a single-AZ instance."
  }
  assert {
    condition     = length(aws_subnet.database) == 2
    error_message = "The DB subnet group needs two AZ subnets without a standby."
  }
  assert {
    condition     = aws_instance.host.instance_type == "t3a.medium"
    error_message = "The initial EC2 candidate must retain 4 GiB capacity."
  }
  assert {
    condition     = aws_db_instance.this.publicly_accessible == false && aws_db_instance.this.storage_encrypted == true
    error_message = "Optimized RDS must be private and encrypted."
  }
  assert {
    condition     = aws_s3_bucket_public_access_block.artifacts.block_public_acls == true && aws_s3_bucket_versioning.artifacts.versioning_configuration[0].status == "Enabled"
    error_message = "Report artifacts must be private and versioned."
  }
  assert {
    condition     = strcontains(data.aws_iam_policy_document.host_assume.json, "ec2.amazonaws.com")
    error_message = "The host role must trust only the EC2 service principal."
  }
  assert {
    condition     = aws_instance.host.metadata_options[0].http_tokens == "required"
    error_message = "The host must require IMDSv2."
  }
  assert {
    condition     = length(aws_security_group.host.egress) == 2
    error_message = "The host must have only HTTPS and database egress rules."
  }
}

run "reject_main_vpc_range" {
  command = plan
  variables { vpc_cidr = "10.40.0.0/16" }
  expect_failures = [var.vpc_cidr]
}
