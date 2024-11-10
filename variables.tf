variable "REGION" {
  default = "eu-west-2"
}

variable "USER" {
  default = "ubuntu"
}

variable "ALLOWED_IPS" {
  description = "List of allowed IP addresses or CIDR blocks"
  type        = list(string)
  default = ["0.0.0.0/0"]
}