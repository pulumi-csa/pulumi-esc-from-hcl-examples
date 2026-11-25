variable "organization" {
  type        = string
  description = "Pulumi Cloud organization that owns the environment"
}

variable "project" {
  type        = string
  description = "ESC project the environment lives in"
  default     = "hcl-esc-example-terraform"
}

variable "environment" {
  type        = string
  description = "ESC environment name"
  default     = "dev"
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "api_token" {
  type        = string
  description = "Example secret stored encrypted in the environment"
  sensitive   = true
}
