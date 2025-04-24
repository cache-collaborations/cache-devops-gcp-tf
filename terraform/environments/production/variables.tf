# terraform/environments/production/variables.tf
variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region to deploy resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone to deploy resources"
  type        = string
  default     = "us-central1-a"
}

variable "project_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "cache"
}

variable "db_password" {
  description = "Password for the database user"
  type        = string
  sensitive   = true
}

variable "api_key" {
  description = "API key for external services"
  type        = string
  sensitive   = true
}

variable "bastion_allowed_cidr" {
  description = "CIDR block allowed to access the bastion host"
  type        = string
  default     = "0.0.0.0/0"  # Should be restricted to specific IPs in production
}

variable "security_email" {
  description = "Email address for security alerts"
  type        = string
  default     = "security@example.com"
}
