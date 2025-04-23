# terraform/modules/database/variables.tf
variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
}

variable "environment" {
  description = "Environment (staging or production)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to host the database"
  type        = string
}

variable "db_instance_name" {
  description = "Name for the DB instance"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "app-database"
}

variable "db_user" {
  description = "Database user"
  type        = string
  default     = "app-user"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}
