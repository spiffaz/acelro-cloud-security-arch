variable "environment" {
  type = string
}

variable "project" {
  type = string
}

variable "location" {
  type    = string
  default = "East US"
}

variable "vnet_cidr" {
  type    = string
  default = "10.1.0.0/16"
}
