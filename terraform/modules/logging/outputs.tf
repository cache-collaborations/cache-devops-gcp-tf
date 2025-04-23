# terraform/modules/logging/outputs.tf
output "elasticsearch_service" {
  value       = kubernetes_service.elasticsearch.metadata[0].name
  description = "The name of the Elasticsearch service"
}

output "kibana_service" {
  value       = kubernetes_service.kibana.metadata[0].name
  description = "The name of the Kibana service"
}

output "logstash_service" {
  value       = kubernetes_service.logstash.metadata[0].name
  description = "The name of the Logstash service"
}

output "kibana_ingress_host" {
  value       = kubernetes_ingress_v1.kibana.status.0.load_balancer.0.ingress.0.ip
  description = "The host of the Kibana ingress"
}

output "namespace" {
  value       = kubernetes_namespace.elk.metadata[0].name
  description = "The name of the ELK namespace"
}
