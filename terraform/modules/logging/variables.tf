# terraform/modules/logging/variables.tf
variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "environment" {
  description = "Environment (staging or production)"
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "elasticsearch_version" {
  description = "Version of Elasticsearch to use"
  type        = string
  default     = "7.15.0"
}

variable "kibana_version" {
  description = "Version of Kibana to use"
  type        = string
  default     = "7.15.0"
}

variable "logstash_version" {
  description = "Version of Logstash to use"
  type        = string
  default     = "7.15.0"
}

variable "elasticsearch_disk_size" {
  description = "Size of disk for Elasticsearch (GB)"
  type        = number
  default     = 10
}
