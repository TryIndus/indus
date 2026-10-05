output "deployment" {
  value = {
    instance_id         = aws_instance.host.id
    host_public_ip      = aws_eip.host.public_ip
    artifact_bucket     = aws_s3_bucket.artifacts.id
    database_endpoint   = aws_db_instance.this.address
    runtime_secret_arns = { for name, secret in aws_secretsmanager_secret.runtime : name => secret.arn }
  }
}
output "identity" {
  value = {
    issuer       = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
    client_id    = aws_cognito_user_pool_client.web.id
    hosted_ui    = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${var.aws_region}.amazoncognito.com"
    userinfo_url = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${var.aws_region}.amazoncognito.com/oauth2/userInfo"
  }
}
