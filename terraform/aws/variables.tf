variable "environment" {
  type = string
}

variable "project" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "bastion_allowed_cidrs" {
  type    = list(string)
  default = []
}
