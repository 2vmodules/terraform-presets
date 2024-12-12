variable "region" {
  type    = string
  default = "us-west-1"
}

variable "env" {
  type = string
}

variable "name" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = null
}

variable "vpc_id" {
  type = string
}

variable "vpc_subnets" {
  type = list(string)
}

variable "vpc_private_cidr_blocks" {
  type = list(string)
}

variable "alb_security_group" {
  type = string
}

variable "alb_listener_arn" {
  type = string
}

variable "custom_origin_host_header" {
  default = "FFG"
  type    = string
}

variable "cluster_name" {
  type = string
}

variable "containers" {
  type = list(object({
    name                 = string
    image                = string
    command              = list(string)
    cpu                  = number
    memory               = number
    min_count            = number
    max_count            = number
    target_cpu_threshold = number
    target_mem_threshold = number
    path                 = string
    port                 = number
    priority             = number
    envs                 = map(string)
    secrets              = map(string)
    health_check         = map(string)
    metrics              = map(string)
  }))
  default = [
    {
      name                 = "web-container"
      image                = "nginx:latest"
      command              = []
      cpu                  = 256
      memory               = 512
      min_count            = 1
      max_count            = 10
      target_cpu_threshold = 75
      target_mem_threshold = 80
      path                 = "/"
      priority             = 20
      port                 = 8080
      envs                 = { ENV_VAR1 = "value1" }
      secrets              = { SECRET1 = "arn:aws:ssm:us-west-1:awsAccountID:parameter/secret1" }

      health_check = {
        matcher = "200"
        path    = "/"
      }

      metrics = {
        path = "/metrics"
        port = "8083"
      }
    },
    {
      name                 = "api-container"
      image                = "my-api:latest"
      command              = ["startup.sh"]
      cpu                  = 512
      memory               = 1024
      min_count            = 1
      max_count            = 10
      target_cpu_threshold = 75
      target_mem_threshold = 80
      path                 = "/api"
      priority             = 10
      port                 = 8081
      envs                 = { ENV_VAR1 = "value1" }
      secrets              = { SECRET1 = "arn:aws:ssm:us-west-1:awsAccountID:parameter/secret1" }

      health_check = {
        matcher = "200"
        path    = "/"
      }

      metrics = {
        path = "/metrics"
        port = "9000"
      }

    }
    # Add more containers as needed
  ]
}
