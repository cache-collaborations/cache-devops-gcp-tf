# terraform/environments/staging/kubernetes.tf
# Kubernetes provider configuration
provider "kubernetes" {
  host                   = "https://${module.kubernetes.cluster_endpoint}"
  token                  = data.google_client_config.provider.access_token
  cluster_ca_certificate = module.kubernetes.cluster_ca_certificate
}

data "google_client_config" "provider" {}

# Application Deployment
resource "kubernetes_deployment" "app" {
  metadata {
    name      = "app"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels = {
      app = "app"
      env = local.environment
    }
  }

  spec {
    replicas = 2  # Fewer replicas in staging

    selector {
      match_labels = {
        app = "app"
      }
    }

    template {
      metadata {
        labels = {
          app = "app"
          env = local.environment
        }
      }

      spec {
        service_account_name = kubernetes_service_account.app.metadata[0].name
        
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
              name = kubernetes_config_map.app_config.metadata[0].name
            }
          }
          
          env_from {
            secret_ref {
              name = kubernetes_secret.app_secrets.metadata[0].name
            }
          }
          
          env {
            name  = "GOOGLE_CLOUD_PROJECT"
            value = var.project_id
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
  
  depends_on = [module.kubernetes]
}

# Kubernetes Service Account
resource "kubernetes_service_account" "app" {
  metadata {
    name      = "app"
    namespace = kubernetes_namespace.app.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = module.kubernetes.app_service_account_email
    }
  }
}

# Application Service
resource "kubernetes_service" "app" {
  metadata {
    name      = "app"
    namespace = kubernetes_namespace.app.metadata[0].name
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

# Application Ingress
resource "kubernetes_ingress_v1" "app" {
  metadata {
    name      = "app-ingress"
    namespace = kubernetes_namespace.app.metadata[0].name
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
              name = kubernetes_service.app.metadata[0].name
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

# Horizontal Pod Autoscaler
resource "kubernetes_horizontal_pod_autoscaler_v2" "app" {
  metadata {
    name      = "app-hpa"
    namespace = kubernetes_namespace.app.metadata[0].name
  }
  
  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.app.metadata[0].name
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
