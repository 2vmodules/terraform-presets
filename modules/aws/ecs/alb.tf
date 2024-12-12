locals {

  containers_map                   = { for i, container in var.containers : tostring(i) => container }
  load_balanced_container_keys     = [for i, container in local.containers_map : i if container.path != ""]
  load_balanced_container_keys_map = tomap({ for k, v in local.load_balanced_container_keys : v => k })
  load_balanced_containers         = [for key in local.load_balanced_container_keys : lookup(local.containers_map, key)]

  ### compact() would be better, but it only works with list of strings, while we have list of objects
  ### https://github.com/hashicorp/terraform/issues/28264
  ### leaving this non-working code just for reference to understand what's going on in lines above
  #
  # load_balanced_containers = compact([
  #   for container in var.containers :
  #   container.path != "" ? {
  #     name         = container.name
  #     path         = container.path
  #     port         = container.port
  #     health_check = container.health_check
  #   } : null
  # ])
}

resource "aws_alb_listener_rule" "https_listener_rule" {
  for_each = { for idx, container in local.load_balanced_containers : idx => container }

  listener_arn = var.alb_listener_arn
  priority     = each.value["priority"]

  action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.service_target_group[each.key].arn
  }

  condition {
    path_pattern {
      values = [each.value["path"]]
    }
  }

  # condition {
  #   http_header {
  #     http_header_name = "X-Custom-Header"
  #     values           = [var.custom_origin_host_header]
  #   }
  # }

  tags = merge({
    Name = each.value["name"]
  }, local.common_tags)
}

resource "aws_alb_target_group" "service_target_group" {
  for_each             = { for idx, container in local.load_balanced_containers : idx => container }
  name                 = each.value["name"]
  port                 = each.value["port"]
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  deregistration_delay = 5
  target_type          = "ip"

  dynamic "health_check" {
    for_each = length(each.value.health_check) == 0 ? [] : [1]

    content {
      healthy_threshold   = 2
      unhealthy_threshold = 2
      interval            = 60
      matcher             = each.value.health_check["matcher"]
      path                = each.value.health_check["path"]
      port                = "traffic-port"
      protocol            = "HTTP"
      timeout             = 30
    }
  }

  tags = merge({
    Name = each.value["name"]
  }, local.common_tags)

  lifecycle {
    create_before_destroy = true
  }

}
