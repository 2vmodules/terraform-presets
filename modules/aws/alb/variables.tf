variable "region" {
  type    = string
  default = "us-west-1"
}

variable "lambda_region" {
  type    = string
  default = "us-east-1"
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

variable "domain_name" {
  type = string
}

variable "idle_timeout" {
  type = number
}

variable "cdn_enabled" {
  type    = bool
  default = true
}

variable "cdn_domain_name" {
  type = string
}

variable "cdn_optimize_images" {
  type    = bool
  default = true
}

# variable "cdn_bucket_names" {
#   type = list(string)
# }

variable "cdn_buckets" {
  type = list(map(string))
  default = [
    {
      name        = "static"
      domain_name = "static.s3.us-east-1.amazonaws.com"
      prefix      = "/*"
    }
    # Add more buckets as needed
  ]
}
