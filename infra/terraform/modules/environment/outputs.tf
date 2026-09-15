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

output "edge" {
  value = {
    application_url              = "https://${var.domain_name}"
    cloudfront_distribution_id   = aws_cloudfront_distribution.this.id
    legacy_next_target_group_arn = aws_lb_target_group.legacy_next.arn
  }
}

output "secret_arns" {
  value = {
    legacy_next = aws_secretsmanager_secret.legacy_next.arn
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

output "migration_foundation" {
  value = {
    artifacts_bucket     = aws_s3_bucket.migration["artifacts"].id
    export_bucket        = aws_s3_bucket.migration["supabase-export"].id
    cognito_user_pool_id = aws_cognito_user_pool.migration.id
    database_secret_arn  = aws_rds_cluster.migration.master_user_secret[0].secret_arn
    rds_proxy_endpoint   = aws_db_proxy.migration.endpoint
    aurora_cluster_arn   = aws_rds_cluster.migration.arn
  }
}

output "shared_ecr_repository_urls" {
  value = var.shared_ecr_repository_urls
}
