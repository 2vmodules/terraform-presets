data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  name       = "${var.env}-${var.name}"

  common_tags = {
    Env        = var.env
    tf-managed = true
    tf-module  = "aws/alb"
  }

  tags = merge({
    Name = local.name
  }, local.common_tags, var.tags)
}

resource "aws_alb" "alb" {
  name            = local.name
  security_groups = [aws_security_group.alb.id]
  subnets         = var.vpc_subnets

  idle_timeout = var.idle_timeout

  tags = local.tags
}

resource "aws_alb_listener" "alb_default_listener_http" {
  load_balancer_arn = aws_alb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = local.tags
}

resource "aws_alb_listener" "alb_default_listener_https" {
  load_balancer_arn = aws_alb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.alb_certificate.arn
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-Ext-2018-06"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Access denied"
      status_code  = "403"
    }
  }

  tags = local.tags

  depends_on = [aws_acm_certificate.alb_certificate]
}

resource "aws_security_group" "alb" {
  name        = local.name
  description = "Security group for ALB"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all egress traffic"
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow ingress HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow ingress HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

### In case of ALB origin in Cloudfront:
#
# data "aws_ec2_managed_prefix_list" "cloudfront" {
#   name = "com.amazonaws.global.cloudfront.origin-facing"
# }

# resource "aws_security_group_rule" "alb_cloudfront_https_ingress_only" {
#   security_group_id = aws_security_group.alb.id
#   description       = "Allow HTTPS access only from CloudFront CIDR blocks"
#   from_port         = 443
#   protocol          = "tcp"
#   prefix_list_ids   = [data.aws_ec2_managed_prefix_list.cloudfront.id]
#   to_port           = 443
#   type              = "ingress"
# }
