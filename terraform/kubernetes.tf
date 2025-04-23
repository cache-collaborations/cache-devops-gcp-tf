# Create Kubernetes provider
provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.current.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

# Get current Google client config
data "google_client_config" "current" {}

# Create production namespace
resource "kubernetes_namespace" "production" {
  metadata {
    name = "production"
  }

  depends_on = [
    google_container_node_pool.primary_nodes
  ]
}

# Create staging namespace
resource "kubernetes_namespace" "staging" {
  metadata {
    name = "staging"
  }

  depends_on = [
    google_container_node_pool.staging_nodes
  ]
}

# Create Kubernetes Service Account for the application in production
resource "kubernetes_service_account" "app_production" {
  metadata {
    name      = "app"
    namespace = kubernetes_namespace.production.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.app_sa.email
    }
  }
}

# Create Kubernetes Service Account for the application in staging
resource "kubernetes_service_account" "app_staging" {
  metadata {
    name      = "app"
    namespace = kubernetes_namespace.staging.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.app_sa.email
    }
  }
}

# Create ConfigMap for the application in production
resource "kubernetes_config_map" "app_config_production" {
  metadata {
    name      = "app-config"
    namespace = kubernetes_namespace.production.metadata[0].name
  }

  data = {
    "CONFIG_ENV" = "production"
    "LOG_LEVEL"  = "info"
  }
}

# Create ConfigMap for the application in staging
resource "kubernetes_config_map" "app_config_staging" {
  metadata {
    name      = "app-config"
    namespace = kubernetes_namespace.staging.metadata[0].name
  }

  data = {
    "CONFIG_ENV" = "staging"
    "LOG_LEVEL"  = "debug"
  }
}

# Create Secret for the application in production
resource "kubernetes_secret" "app_secrets_production" {
  metadata {
    name      = "app-secrets"
    namespace = kubernetes_namespace.production.metadata[0].name
  }

  data = {
    "DB_SECRET_NAME"   = google_secret_manager_secret.db_connection.secret_id
    "PUBSUB_TOPIC"     = google_pubsub_topic.app_topic.name
    "LOGSTASH_HOST"    = "http://logstash.elk.svc.cluster.local:8080"
  }
}

# Create Secret for the application in staging
resource "kubernetes_secret" "app_secrets_staging" {
  metadata {
    name      = "app-secrets"
    namespace = kubernetes_namespace.staging.metadata[0].name
  }

  data = {
    "DB_SECRET_NAME"   = google_secret_manager_secret.db_connection.secret_id
    "PUBSUB_TOPIC"     = google_pubsub_topic.app_topic.name
    "LOGSTASH_HOST"    = "http://logstash.elk.svc.cluster.local:8080"
  }
}

# Create Deployment for the application in production
resource "kubernetes_deployment" "app_production" {
  metadata {
    name      = "app"
    namespace = kubernetes_namespace.production.metadata[0].name
  }

  spec {
    replicas = 4

    selector {
      match_labels = {
        app = "app"
      }
    }

    template {
      metadata {
        labels = {
          app = "app"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.app_production.metadata[0].name

        container {
          name  = "app"
          image = "${var.region}-docker.pkg.dev/${var.project_id}/app-registry/app:latest"

          port {
            container_port = 8080
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.app_config_production.metadata[0].name
            }
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.app_secrets_production.metadata[0].name
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_version.db_connection_version
  ]
}

# Create Deployment for the application in staging
resource "kubernetes_deployment" "app_staging" {
  metadata {
    name      = "app"
    namespace = kubernetes_namespace.staging.metadata[0].name
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "app"
      }
    }

    template {
      metadata {
        labels = {
          app = "app"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.app_staging.metadata[0].name

        container {
          name  = "app"
          image = "${var.region}-docker.pkg.dev/${var.project_id}/app-registry/app:staging"

          port {
            container_port = 8080
          }

          resources {
            limits = {
              cpu    = "300m"
              memory = "256Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.app_config_staging.metadata[0].name
            }
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.app_secrets_staging.metadata[0].name
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_version.db_connection_version
  ]
}

# Create Service for the application in production
resource "kubernetes_service" "app_production" {
  metadata {
    name      = "app"
    namespace = kubernetes_namespace.production.metadata[0].name
  }

  spec {
    selector = {
      app = "app"
    }

    port {
      port        = 80
      target_port = 8080
    }

    type = "ClusterIP"
  }
}

# Create Service for the application in staging
resource "kubernetes_service" "app_staging" {
  metadata {
    name      = "app"
    namespace = kubernetes_namespace.staging.metadata[0].name
  }

  spec {
    selector = {
      app = "app"
    }

    port {
      port        = 80
      target_port = 8080
    }

    type = "ClusterIP"
  }
}

# Create Ingress for the application in production
resource "kubernetes_ingress_v1" "app_production" {
  metadata {
    name      = "app-ingress"
    namespace = kubernetes_namespace.production.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class" = "gce"
    }
  }

  spec {
    rule {
      http {
        path {
          path = "/*"
          backend {
            service {
              name = kubernetes_service.app_production.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}

# Create Ingress for the application in staging
resource "kubernetes_ingress_v1" "app_staging" {
  metadata {
    name      = "app-ingress"
    namespace = kubernetes_namespace.staging.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class" = "gce"
    }
  }

  spec {
    rule {
      http {
        path {
          path = "/*"
          backend {
            service {
              name = kubernetes_service.app_staging.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}

# Create HorizontalPodAutoscaler for the application in production
resource "kubernetes_horizontal_pod_autoscaler_v2" "app_production" {
  metadata {
    name      = "app-hpa"
    namespace = kubernetes_namespace.production.metadata[0].name
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.app_production.metadata[0].name
    }

    min_replicas = 4
    max_replicas = 10

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
}

# Create HorizontalPodAutoscaler for the application in staging
resource "kubernetes_horizontal_pod_autoscaler_v2" "app_staging" {
  metadata {
    name      = "app-hpa"
    namespace = kubernetes_namespace.staging.metadata[0].name
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.app_staging.metadata[0].name
    }

    min_replicas = 2
    max_replicas = 5

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
}

# Create NetworkPolicy for the application in production
resource "kubernetes_network_policy" "app_production" {
  metadata {
    name      = "app-network-policy"
    namespace = kubernetes_namespace.production.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app = "app"
      }
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            kubernetes.io/metadata.name = "kube-system"
          }
        }
      }
      from {
        ip_block {
          cidr = "0.0.0.0/0"
        }
      }
    }

    egress {
      to {
        ip_block {
          cidr = "0.0.0.0/0"
        }
      }
    }

    policy_types = ["Ingress", "Egress"]
  }
}

# Create NetworkPolicy for the application in staging
resource "kubernetes_network_policy" "app_staging" {
  metadata {
    name      = "app-network-policy"
    namespace = kubernetes_namespace.staging.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app = "app"
      }
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            kubernetes.io/metadata.name = "kube-system"
          }
        }
      }
      from {
        ip_block {
          cidr = "0.0.0.0/0"
        }
      }
    }

    egress {
      to {
        ip_block {
          cidr = "0.0.0.0/0"
        }
      }
    }

    policy_types = ["Ingress", "Egress"]
  }
}
