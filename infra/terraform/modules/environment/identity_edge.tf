resource "aws_acm_certificate" "application" {
  domain_name               = var.domain_name
  subject_alternative_names = ["origin.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.common_tags
}

resource "aws_route53_record" "certificate_validation" {
  for_each = {
    for option in aws_acm_certificate.application.domain_validation_options : option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.public.zone_id
  name    = each.value.name
  records = [each.value.record]
  ttl     = 60
  type    = each.value.type
}

resource "aws_acm_certificate_validation" "application" {
  certificate_arn         = aws_acm_certificate.application.arn
  validation_record_fqdns = values(aws_route53_record.certificate_validation)[*].fqdn
}

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "random_password" "cloudfront_origin" {
  length  = 48
  special = false
}

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "Allow CloudFront origin-facing traffic only."
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTPS from CloudFront origin-facing addresses"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  egress {
    description = "Application traffic inside the VPC"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Market stream traffic inside the VPC"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-alb"
  })
}

resource "aws_security_group_rule" "cluster_from_alb" {
  description              = "Legacy Next.js traffic from the shared ALB"
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "market_data_from_alb" {
  description              = "Market stream traffic from the shared ALB"
  type                     = "ingress"
  from_port                = 8081
  to_port                  = 8081
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.alb.id
}

resource "aws_lb" "this" {
  name                       = substr("${local.name}-web", 0, 32)
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = values(aws_subnet.public)[*].id
  enable_deletion_protection = local.production
  drop_invalid_header_fields = true

  tags = local.common_tags
}

resource "aws_lb_target_group" "legacy_next" {
  name        = substr("${local.name}-legacy", 0, 32)
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200-399"
    path                = "/api/health?mode=ready"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = local.common_tags
}

resource "aws_lb_target_group" "platform_api" {
  name        = substr("${local.name}-api", 0, 32)
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200-399"
    path                = "/readyz"
    timeout             = 5
    unhealthy_threshold = 2
  }
  tags = local.common_tags
}

resource "aws_lb_target_group" "market_data" {
  name        = substr("${local.name}-stream", 0, 32)
  port        = 8081
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200-399"
    path                = "/health/ready"
    timeout             = 5
    unhealthy_threshold = 2
  }
  tags = local.common_tags
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.application.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
}

resource "aws_lb_listener_rule" "cloudfront_origin" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.legacy_next.arn
  }

  condition {
    http_header {
      http_header_name = "X-Indus-Origin-Verify"
      values           = [random_password.cloudfront_origin.result]
    }
  }
}

resource "aws_lb_listener_rule" "platform_api" {
  count        = var.replacement_platform_enabled ? 1 : 0
  listener_arn = aws_lb_listener.https.arn
  priority     = 10
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.platform_api.arn
  }
  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
  condition {
    http_header {
      http_header_name = "X-Indus-Origin-Verify"
      values           = [random_password.cloudfront_origin.result]
    }
  }
}

resource "aws_lb_listener_rule" "market_data" {
  count        = var.replacement_platform_enabled ? 1 : 0
  listener_arn = aws_lb_listener.https.arn
  priority     = 20
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.market_data.arn
  }
  condition {
    path_pattern {
      values = ["/stream/*"]
    }
  }
  condition {
    http_header {
      http_header_name = "X-Indus-Origin-Verify"
      values           = [random_password.cloudfront_origin.result]
    }
  }
}

resource "aws_route53_record" "origin" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = "origin.${var.domain_name}"
  type    = "A"

  alias {
    evaluate_target_health = true
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
  }
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

resource "aws_cloudfront_origin_access_control" "web" {
  name                              = "${local.name}-web"
  description                       = "Signed access to the replacement web assets"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "spa" {
  name    = "${local.name}-spa"
  runtime = "cloudfront-js-2.0"
  code    = <<-JS
    function handler(event) {
      var request = event.request;
      if (!request.uri.includes('.')) request.uri = '/index.html';
      return request;
    }
  JS
}

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${local.name} application edge"
  aliases         = [var.domain_name]
  price_class     = "PriceClass_100"
  web_acl_id      = null

  origin {
    domain_name = aws_route53_record.origin.fqdn
    origin_id   = "aws-alb"

    custom_header {
      name  = "X-Forwarded-Host"
      value = var.domain_name
    }

    custom_header {
      name  = "X-Indus-Origin-Verify"
      value = random_password.cloudfront_origin.result
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    domain_name              = aws_s3_bucket.data["web"].bucket_regional_domain_name
    origin_id                = "static-web"
    origin_path              = "/current"
    origin_access_control_id = aws_cloudfront_origin_access_control.web.id
  }

  default_cache_behavior {
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD", "OPTIONS"]
    target_origin_id         = var.replacement_platform_enabled ? "static-web" : "aws-alb"
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = var.replacement_platform_enabled ? data.aws_cloudfront_cache_policy.caching_optimized.id : data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = var.replacement_platform_enabled ? null : data.aws_cloudfront_origin_request_policy.all_viewer.id
    compress                 = true

    dynamic "function_association" {
      for_each = var.replacement_platform_enabled ? [1] : []
      content {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.spa.arn
      }
    }
  }

  ordered_cache_behavior {
    path_pattern             = "/api/*"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD", "OPTIONS"]
    target_origin_id         = "aws-alb"
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
    compress                 = true
  }

  ordered_cache_behavior {
    path_pattern             = "/stream/*"
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD", "OPTIONS"]
    target_origin_id         = "aws-alb"
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
    compress                 = false
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.application.certificate_arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }

  tags = local.common_tags
}

data "aws_iam_policy_document" "web_bucket" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.data["web"].arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "web" {
  bucket = aws_s3_bucket.data["web"].id
  policy = data.aws_iam_policy_document.web_bucket.json
}

resource "aws_route53_record" "application" {
  zone_id         = data.aws_route53_zone.public.zone_id
  name            = var.domain_name
  type            = "A"
  allow_overwrite = true

  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
  }
}
