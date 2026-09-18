output "cluster" {
  value = {
    name                      = aws_eks_cluster.this.name
    vpc_id                    = aws_vpc.this.id
    endpoint                  = aws_eks_cluster.this.endpoint
    certificate_authority     = aws_eks_cluster.this.certificate_authority[0].data
    oidc_provider_arn         = aws_iam_openid_connect_provider.eks.arn
    cluster_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  }
}

output "network" {
  value = { vpc_cidr = aws_vpc.this.cidr_block }
}

output "edge" {
  value = {
    application_url               = "https://${var.domain_name}"
    cloudfront_distribution_id    = aws_cloudfront_distribution.this.id
    legacy_next_target_group_arn  = aws_lb_target_group.legacy_next.arn
    platform_api_target_group_arn = aws_lb_target_group.platform_api.arn
    market_data_target_group_arn  = aws_lb_target_group.market_data.arn
  }
}

output "secret_arns" {
  value = {
    legacy_next        = aws_secretsmanager_secret.legacy_next.arn
    platform_api       = aws_secretsmanager_secret.replacement["platform-api"].arn
    market_data        = aws_secretsmanager_secret.replacement["market-data"].arn
    research_worker    = aws_secretsmanager_secret.replacement["research-worker"].arn
    database_migration = aws_secretsmanager_secret.replacement["database-migration"].arn
  }
}

output "workload_role_arns" {
  value = {
    for key, role in aws_iam_role.workload : key => role.arn
  }
}

output "observability" {
  value = {
    alert_topic_arn = aws_sns_topic.alerts.arn
  }
}

output "data_platform" {
  value = {
    artifacts_bucket      = aws_s3_bucket.data["artifacts"].id
    raw_events_bucket     = aws_s3_bucket.data["raw-events"].id
    web_bucket            = aws_s3_bucket.data["web"].id
    export_bucket         = aws_s3_bucket.data["exports"].id
    cognito_user_pool_id  = aws_cognito_user_pool.this.id
    database_secret_arn   = aws_rds_cluster.data.master_user_secret[0].secret_arn
    rds_proxy_endpoint    = aws_db_proxy.data.endpoint
    aurora_cluster_arn    = aws_rds_cluster.data.arn
    redis_endpoint        = aws_elasticache_serverless_cache.application.endpoint[0].address
    redis_port            = aws_elasticache_serverless_cache.application.endpoint[0].port
    redis_cache_name      = aws_elasticache_serverless_cache.application.name
    redis_user            = aws_elasticache_user.application.user_name
    msk_bootstrap_brokers = aws_msk_serverless_cluster.events.bootstrap_brokers_sasl_iam
  }
}

output "replacement_platform" {
  value = {
    enabled            = var.replacement_platform_enabled
    temporal_address   = var.temporal_address
    temporal_namespace = var.temporal_namespace
  }
}

output "identity" {
  value = {
    user_pool_id = aws_cognito_user_pool.this.id
    client_id    = aws_cognito_user_pool_client.web.id
    issuer       = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
    hosted_ui    = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${var.aws_region}.amazoncognito.com"
    userinfo_url = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${var.aws_region}.amazoncognito.com/oauth2/userInfo"
  }
}

output "shared_ecr_repository_urls" {
  value = var.shared_ecr_repository_urls
}
