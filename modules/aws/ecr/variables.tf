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

variable "ecr_repositories" {
  type    = list(string)
  default = []
}
