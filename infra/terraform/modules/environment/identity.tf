resource "aws_cognito_user_pool" "this" {
  name                     = local.name
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  deletion_protection      = local.production ? "ACTIVE" : "INACTIVE"
  mfa_configuration        = "OFF"

  dynamic "email_configuration" {
    for_each = var.enable_branded_cognito_email ? [1] : []
    content {
      email_sending_account = "DEVELOPER"
      from_email_address    = "Indus <notifications@${var.domain_name}>"
      source_arn            = aws_ses_domain_identity.cognito[0].arn
    }
  }

  dynamic "verification_message_template" {
    for_each = var.enable_branded_cognito_email ? [1] : []
    content {
      default_email_option = "CONFIRM_WITH_CODE"
      email_subject        = "Your Indus verification code"
      email_message = templatefile("${path.module}/templates/cognito-verification.html", {
        app_url = "https://${var.domain_name}/auth"
      })
    }
  }

  password_policy {
    minimum_length                   = 14
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 3
  }

  tags = local.common_tags

  depends_on = [aws_ses_domain_identity_verification.cognito, aws_route53_record.cognito_dkim]
}

resource "aws_ses_domain_identity" "cognito" {
  count  = var.enable_branded_cognito_email ? 1 : 0
  domain = var.domain_name
}

resource "aws_route53_record" "cognito_ses_verification" {
  count   = var.enable_branded_cognito_email ? 1 : 0
  zone_id = data.aws_route53_zone.public.zone_id
  name    = "_amazonses.${var.domain_name}"
  type    = "TXT"
  ttl     = 300
  records = [aws_ses_domain_identity.cognito[0].verification_token]
}

resource "aws_ses_domain_identity_verification" "cognito" {
  count      = var.enable_branded_cognito_email ? 1 : 0
  domain     = aws_ses_domain_identity.cognito[0].domain
  depends_on = [aws_route53_record.cognito_ses_verification]
}

resource "aws_ses_domain_dkim" "cognito" {
  count  = var.enable_branded_cognito_email ? 1 : 0
  domain = aws_ses_domain_identity.cognito[0].domain
}

resource "aws_route53_record" "cognito_dkim" {
  count   = var.enable_branded_cognito_email ? 3 : 0
  zone_id = data.aws_route53_zone.public.zone_id
  name    = "${aws_ses_domain_dkim.cognito[0].dkim_tokens[count.index]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["${aws_ses_domain_dkim.cognito[0].dkim_tokens[count.index]}.dkim.amazonses.com"]
}

resource "aws_cognito_user_pool_client" "web" {
  name         = "web"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  explicit_auth_flows                  = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH"]
  supported_identity_providers         = ["COGNITO"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  callback_urls                        = var.cognito_callback_urls
  logout_urls                          = var.cognito_logout_urls
  access_token_validity                = 60
  id_token_validity                    = 60
  refresh_token_validity               = 30

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${local.name}-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.this.id
}
