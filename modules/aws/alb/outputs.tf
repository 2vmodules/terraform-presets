output "alb_id" {
  value       = aws_alb.alb.id
  description = "Application Load Balancer ID"
}

output "alb_aws_security_group_id" {
  value       = aws_security_group.alb.id
  description = "Application Load Balancer ID"
}

output "alb_listener_https_arn" {
  value       = aws_alb_listener.alb_default_listener_https.arn
  description = "Application Load Balancer HTTPS Listener ARN"
}

output "alb_listener_http_arn" {
  value       = aws_alb_listener.alb_default_listener_http.arn
  description = "Application Load Balancer HTTP Listener ARN"
}
