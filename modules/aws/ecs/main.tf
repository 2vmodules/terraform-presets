data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  common_tags = {
    Env        = var.env
    tf-managed = true
    tf-module  = "aws/ecs"
  }

  tags = merge({
    Name = var.cluster_name
  }, local.common_tags, var.tags)
}

### ECS CLUSTER

resource "aws_ecs_cluster" "cluster" {
  name = var.cluster_name
  tags = local.tags
}

### ECS TASKS

resource "aws_cloudwatch_log_group" "log_group" {
  name              = var.cluster_name
  retention_in_days = 30

  tags = local.tags
}

resource "aws_ecs_task_definition" "container_task_definitions" {
  for_each                 = { for idx, container in var.containers : idx => container }
  family                   = each.value["name"]
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.exec_role.arn
  task_role_arn            = aws_iam_role.task_role.arn
  cpu                      = each.value["cpu"]
  memory                   = each.value["memory"]

  container_definitions = jsonencode([
    {
      name    = each.value["name"]
      image   = each.value["image"]
      command = each.value["command"]
      cpu     = each.value["cpu"]
      memory  = each.value["memory"]
      portMappings = [
        {
          containerPort = each.value["port"]
        }
      ]

      environment = [for key, value in each.value["envs"] :
        {
          name  = key
          value = value
        }
      ]

      secrets = [for key, value in each.value["secrets"] :
        {
          name      = key
          valueFrom = value
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.log_group.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = each.value["name"]
        }
      }
    },
    {
      name    = "ecs-exporter"
      image   = "quay.io/prometheuscommunity/ecs-exporter:v0.2.1"
      command = null
      cpu     = 0
      memory  = null
      portMappings = [
        {
          containerPort = 9779
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.log_group.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = each.value["name"]
        }
      }
    }
  ])

  tags = merge(
    try(
      {
        METRICS_PATH = each.value.metrics["path"]
        METRICS_PORT = each.value.metrics["port"]
      },
      {}
    ),
    {
      ECS_METRICS_PATH = "/metrics"
      ECS_METRICS_PORT = 9779
    },
    local.tags
  )

}

resource "aws_service_discovery_private_dns_namespace" "service_discovery_namespace" {
  name        = var.cluster_name
  description = "${title(var.cluster_name)} Service Discovery Namespace"
  vpc         = var.vpc_id
}

resource "aws_service_discovery_service" "service_discovery_service" {
  for_each = { for idx, container in var.containers : idx => container }

  name = each.value["name"]

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.service_discovery_namespace.id

    dns_records {
      ttl  = 15
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_ecs_service" "container_service" {
  for_each                           = { for idx, container in var.containers : idx => container }
  name                               = each.value["name"]
  cluster                            = aws_ecs_cluster.cluster.id
  task_definition                    = aws_ecs_task_definition.container_task_definitions[each.key].arn
  desired_count                      = each.value["min_count"]
  deployment_minimum_healthy_percent = floor(100 / each.value["min_count"])
  deployment_maximum_percent         = each.value["min_count"] == 1 ? 200 : 150
  launch_type                        = "FARGATE"

  dynamic "load_balancer" {
    for_each = each.value.path == "" ? [] : [1]

    content {
      target_group_arn = aws_alb_target_group.service_target_group[local.load_balanced_container_keys_map[each.key]].arn
      container_name   = each.value["name"]
      container_port   = each.value["port"]
    }
  }

  network_configuration {
    subnets         = var.vpc_subnets
    security_groups = [aws_security_group.ecs[each.key].id]
  }

  service_registries {
    registry_arn = aws_service_discovery_service.service_discovery_service[each.key].arn
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

}

resource "aws_security_group" "ecs" {
  for_each    = { for idx, container in var.containers : idx => container }
  name        = each.value["name"]
  description = "Allow incoming traffic for ECS containers"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = each.value["port"]
    to_port         = each.value["port"]
    protocol        = "tcp"
    security_groups = [var.alb_security_group]
  }

  ingress {
    from_port       = each.value["port"]
    to_port         = each.value["port"]
    protocol        = "tcp"
    cidr_blocks     = var.vpc_private_cidr_blocks
  }

  ingress {
    from_port   = 9779
    to_port     = 9779
    protocol    = "tcp"
    cidr_blocks = var.vpc_private_cidr_blocks
  }

  dynamic "ingress" {
    for_each = length(each.value.metrics) > 0 ? [1] : []

    content {
      from_port   = each.value.metrics["port"]
      to_port     = each.value.metrics["port"]
      protocol    = "tcp"
      cidr_blocks = var.vpc_private_cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({
    Name = each.value["name"]
  }, local.common_tags)
}

resource "aws_appautoscaling_target" "ecs_target" {
  for_each           = { for idx, container in var.containers : idx => container }
  max_capacity       = each.value["max_count"]
  min_capacity       = each.value["min_count"]
  resource_id        = format("%s/%s/%s", "service", aws_ecs_cluster.cluster.name, aws_ecs_service.container_service[each.key].name)
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_cpu_policy" {
  for_each           = { for idx, container in var.containers : idx => container }
  name               = format("%s-%s", each.value["name"], "cpu-policy")
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = each.value["target_cpu_threshold"]

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "ecs_memory_policy" {
  for_each           = { for idx, container in var.containers : idx => container }
  name               = format("%s-%s", each.value["name"], "memory-policy")
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = each.value["target_mem_threshold"]

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}

### IAM

resource "aws_iam_role" "exec_role" {
  name = "${var.cluster_name}-exec-role"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ecs-tasks.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
  tags = {
    Name = "${var.cluster_name}-exec-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_exec_policy" {
  role       = aws_iam_role.exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task_role" {
  name = "${var.cluster_name}-task-role"

  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "ecs-tasks.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
  tags = {
    Name = "${var.cluster_name}-task-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_policy" {
  role       = aws_iam_role.task_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Ability to obtain SSM parameters

resource "aws_iam_policy" "ssm_get_policy" {
  name        = "${var.cluster_name}-ssm-get-policy"
  description = "Allows to get SSM parameters, including encrypted ones"
  policy      = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter*",
        "secretsmanager:GetSecret*",
        "kms:Decrypt"
      ],
      "Resource": [
        "arn:aws:ssm:${var.region}:${local.account_id}:parameter/*",
        "arn:aws:kms:${var.region}:${local.account_id}:key/*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs_exec_role" {
  role       = aws_iam_role.exec_role.name
  policy_arn = aws_iam_policy.ssm_get_policy.arn
}

resource "aws_iam_role_policy_attachment" "ecs_task_role" {
  role       = aws_iam_role.task_role.name
  policy_arn = aws_iam_policy.ssm_get_policy.arn
}
