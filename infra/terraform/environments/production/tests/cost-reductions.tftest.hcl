mock_provider "aws" {
  override_during = plan
  mock_resource "aws_acm_certificate_validation" {
    defaults = { certificate_arn = "arn:aws:acm:us-east-1:111111111111:certificate/test" }
  }
  mock_resource "aws_acm_certificate" {
    defaults = { arn = "arn:aws:acm:us-east-1:111111111111:certificate/test", domain_validation_options = [{ domain_name = "tryindus.ca", resource_record_name = "_test.tryindus.ca", resource_record_type = "CNAME", resource_record_value = "validation.example.com" }] }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b"] }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_resource "aws_rds_cluster" {
    defaults = {
      id                 = "indus-production"
      endpoint           = "aurora.test.local"
      master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-1:111111111111:secret:test", secret_status = "active", kms_key_id = "test" }]
    }
  }
  mock_resource "aws_db_proxy" {
    defaults = { endpoint = "proxy.test.local" }
  }
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:us-east-1:111111111111:indus-production-alerts" }
  }
}
mock_provider "tls" {}
mock_provider "random" {}

variables {
  account_id                  = "111111111111"
  cluster_public_access_cidrs = ["203.0.113.10/32"]
  monthly_budget_usd          = 300
  legacy_next_secret_name     = "test-legacy"
  vpc_cidr                    = "10.40.0.0/16"
  domain_name                 = "tryindus.ca"
  route53_zone_name           = "tryindus.ca"
  legacy_origin_hostname      = "legacy.example.com"
  shared_ecr_repository_urls  = { legacy-next = "example.com/legacy-next" }
}

run "proxy_remains_default" {
  command = plan
  assert {
    condition     = output.environment.data_platform.database_access_mode == "proxy"
    error_message = "The default must not cut over existing database clients."
  }
}
run "supplementary_monitoring_is_suspended_by_default" {
  command = plan
  assert {
    condition     = output.environment.observability.alert_topic_arn == null
    error_message = "Supplementary alerting and its SNS topic must be absent by default."
  }
}
run "supplementary_monitoring_can_be_restored" {
  command = plan
  variables { enable_supplementary_monitoring = true }
  assert {
    condition     = output.environment.observability.alert_topic_arn == "arn:aws:sns:us-east-1:111111111111:indus-production-alerts"
    error_message = "Operators must be able to restore supplementary alerting explicitly."
  }
}
run "prepare_direct_retains_proxy" {
  command = plan
  variables { database_access_mode = "prepare-direct" }
  assert {
    condition     = output.environment.data_platform.rds_proxy_endpoint != null && output.environment.data_platform.database_endpoint == output.environment.data_platform.aurora_endpoint
    error_message = "Preparation must expose Aurora while retaining the rollback proxy."
  }
}
run "direct_removes_proxy" {
  command = plan
  variables { database_access_mode = "direct" }
  assert {
    condition     = output.environment.data_platform.rds_proxy_endpoint == null && output.environment.data_platform.database_endpoint == output.environment.data_platform.aurora_endpoint
    error_message = "Direct mode must remove the proxy and retain the Aurora endpoint."
  }
}
run "reject_unknown_mode" {
  command = plan
  variables { database_access_mode = "typo" }
  expect_failures = [var.database_access_mode]
}
run "retain_security_logs" {
  command = plan
  variables { eks_log_types = ["api"] }
  expect_failures = [var.eks_log_types]
}
