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
    condition     = length(aws_sns_topic.alerts) == 0 && length(aws_budgets_budget.monthly) == 0 && length(aws_route53_health_check.preview) == 0
    error_message = "Supplementary alerts, budget notifications, and health checks must be absent by default."
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.host_status) == 0 && length(aws_db_event_subscription.database) == 0 && length(aws_iam_role_policy_attachment.cloudwatch) == 0
    error_message = "Optimized supplementary monitoring and agent permissions must be off by default."
  }
  assert {
    condition     = aws_db_instance.this.performance_insights_enabled == false && aws_db_instance.this.backup_retention_period == 7
    error_message = "Disable optional RDS insights without disabling database backups."
  }
  assert {
    condition     = aws_ssm_parameter.supplementary_monitoring.value == "false"
    error_message = "The host must receive the disabled monitoring setting by default."
  }
  assert {
    condition     = aws_cognito_user_pool.this.mfa_configuration == "OFF"
    error_message = "The optimized profile does not enable Cognito MFA."
  }
  assert {
    condition     = aws_cognito_user_pool_client.web.prevent_user_existence_errors == "ENABLED"
    error_message = "The optimized Cognito client must avoid revealing account existence."
  }
  assert {
    condition     = aws_db_instance.this.multi_az == false
    error_message = "Optimized RDS must remain a single-AZ instance."
  }
  assert {
    condition     = length(aws_subnet.database) == 2
    error_message = "The DB subnet group needs two AZ subnets without a standby."
  }
  assert {
    condition     = aws_instance.host.instance_type == "t3a.medium" && aws_db_instance.this.instance_class == "db.t4g.micro"
    error_message = "The minimal profile must retain a 4-GiB host and use db.t4g.micro database capacity."
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
}

run "supplementary_monitoring_can_be_restored" {
  command = plan
  variables {
    enable_supplementary_monitoring = true
  }
  assert {
    condition     = length(aws_sns_topic.alerts) == 1 && length(aws_budgets_budget.monthly) == 1 && length(aws_route53_health_check.preview) == 1
    error_message = "Enabling the flag must provision alerts, budget notifications, and HTTPS health checks."
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.host_status) == 1 && length(aws_db_event_subscription.database) == 1 && length(aws_iam_role_policy_attachment.cloudwatch) == 1
    error_message = "Enabling the flag must restore host and database monitoring."
  }
  assert {
    condition     = aws_route53_health_check.preview[0].fqdn == "tryindus.ca"
    error_message = "The HTTPS health check must follow the production root domain."
  }
  assert {
    condition     = aws_db_instance.this.performance_insights_enabled == true && aws_ssm_parameter.supplementary_monitoring.value == "true"
    error_message = "Enabling the flag must restore RDS insights and publish the host agent setting."
  }
}

run "branded_cognito_confirmation_email_is_opt_in" {
  command = plan
  variables {
    enable_branded_cognito_email = true
    branded_email_zone_id        = "Z0123456789EXAMPLE"
  }
  assert {
    condition     = aws_cognito_user_pool.this.email_configuration[0].email_sending_account == "DEVELOPER"
    error_message = "Branded verification emails must use the optimized SES identity when explicitly enabled."
  }
  assert {
    condition     = aws_ses_domain_identity.cognito[0].domain == "tryindus.ca"
    error_message = "Branded email must use the existing production domain."
  }
  assert {
    condition     = strcontains(aws_cognito_user_pool.this.verification_message_template[0].email_message, "{####}")
    error_message = "The branded verification template must include Cognito's confirmation code placeholder."
  }
  assert {
    condition     = aws_cognito_user_pool.this.verification_message_template[0].default_email_option == "CONFIRM_WITH_CODE"
    error_message = "Branded verification must keep users in the Indus code-entry experience."
  }
}

run "reject_main_vpc_range" {
  command = plan
  variables { vpc_cidr = "10.40.0.0/16" }
  expect_failures = [var.vpc_cidr]
}
