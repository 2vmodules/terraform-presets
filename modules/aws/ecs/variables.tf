variable "region" {
  type    = string
  default = "eu-central-1"
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

variable "vpc_private_cidr_blocks" {
  type = list(string)
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
    path                 = list(string)
    port                 = number
    service_domain       = string
    priority             = number
    envs                 = map(string)
    secrets              = map(string)
    health_check         = map(string)
    volumes = optional(list(object({
      name           = string
      container_path = string
      read_only      = optional(bool)
    })), [])
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
      path                 = ["/"]
      priority             = 20
      port                 = 8080
      service_domain       = "domaon.example.com"
      envs                 = { ENV_VAR1 = "value1" }
      secrets              = { SECRET1 = "arn:aws:ssm:eu-central-1:awsAccountID:parameter/secret1" }

      health_check = {
        matcher = "200"
        path    = "/"
      }
      volumes = [
        {
          name                        = "web-container-efs-storage"
          container_path              = "/opt/web-container-data"
          read_only                   = false
        }
      ]
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
      path                 = ["/api"]
      priority             = 10
      port                 = 8081
      service_domain       = "domaon.example.com"
      envs                 = { ENV_VAR1 = "value1" }
      secrets              = { SECRET1 = "arn:aws:ssm:eu-central-1:awsAccountID:parameter/secret1" }

      health_check = {
        matcher = "200"
        path    = "/"
      }
      volumes = [
        {
          name                        = "api-container-efs-storage"
          container_path              = "/opt/api-container-data"
          read_only                   = false
        }
      ]
    }
    # Add more containers as needed
  ]
}

variable "efs_enabled" {
  description = "Enable EFS for shared storage"
  type        = bool
  default     = false
}

variable "efs_performance_mode" {
  description = "EFS performance mode"
  type        = string
  default     = "generalPurpose"
}

variable "efs_throughput_mode" {
  description = "EFS throughput mode"
  type        = string
  default     = "bursting"
}

variable "efs_provisioned_throughput" {
  description = "Provisioned throughput in MiB/s (only valid when throughput_mode is provisioned)"
  type        = number
  default     = null
}