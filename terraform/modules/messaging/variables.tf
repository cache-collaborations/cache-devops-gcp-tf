# terraform/modules/messaging/variables.tf
variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "environment" {
  description = "Environment (staging or production)"
  type        = string
}

variable "topic_name" {
  description = "Name of the Pub/Sub topic"
  type        = string
}

variable "subscription_ack_deadline" {
  description = "Acknowledgement deadline for the subscription (seconds)"
  type        = number
  default     = 20
}

variable "message_retention_duration" {
  description = "How long to retain unacknowledged messages"
  type        = string
  default     = "604800s" # 7 days
}
