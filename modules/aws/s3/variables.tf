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

variable "public" {
  type    = bool
  default = true
}

variable "replication" {
  type    = bool
  default = false
}

variable "object_ownership" {
  type    = string
  default = "ObjectWriter"
}
