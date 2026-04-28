variable "region" {
  default = "us-east-1"
}

variable "key_pair_name" {
  description = "Name of EC2 key pair"
  default     = "voting-app-key"
}