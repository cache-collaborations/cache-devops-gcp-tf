# Variables
variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "environment" {
  description = "Environment (staging or production)"
  type        = string
}

variable "prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "cache"
}
