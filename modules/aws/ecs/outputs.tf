output "ecs_cluster_id" {
  description = "ECS cluster ID"
  value       = aws_ecs_cluster.cluster.id
}

output "ecs_task_exec_role_name" {
  description = "ECS task execution role name"
  value       = aws_iam_role.exec_role.name
}

output "ecs_task_role_name" {
  description = "ECS task role name"
  value       = aws_iam_role.task_role.name
}

output "ecs_task_exec_role_arn" {
  description = "ECS task execution role name"
  value       = aws_iam_role.exec_role.arn
}

output "ecs_task_role_arn" {
  description = "ECS task role name"
  value       = aws_iam_role.task_role.arn
}

output "ecs_security_group_ids" {
  description = "ECS security group IDs"
  value       = values(aws_security_group.ecs)[*].id
}

output "ecs_cloudwatch_group_name" {
  description = "ECS cloudwatch group name"
  value       = aws_cloudwatch_log_group.log_group.name
}

output "ecs_service_discovery_namespace_id" {
  description = "ECS service discovery namespace ID"
  value       = aws_service_discovery_private_dns_namespace.service_discovery_namespace.id
}
