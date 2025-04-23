# Namespace for ELK stack
resource "kubernetes_namespace" "elk" {
  metadata {
    name = "elk"
  }

  depends_on = [
    google_container_node_pool.primary_nodes
  ]
}

# Elasticsearch StatefulSet
resource "kubernetes_stateful_set" "elasticsearch" {
  metadata {
    name      = "elasticsearch"
    namespace = kubernetes_namespace.elk.metadata[0].name
  }

  spec {
    service_name = "elasticsearch"
    replicas     = 1

    selector {
      match_labels = {
        app = "elasticsearch"
      }
    }

    template {
      metadata {
        labels = {
          app = "elasticsearch"
        }
      }

      spec {
        container {
          name  = "elasticsearch"
          image = "docker.elastic.co/elasticsearch/elasticsearch:7.15.0"

          port {
            container_port = 9200
            name           = "rest"
          }

          port {
            container_port = 9300
            name           = "inter-node"
          }

          resources {
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }

          env {
            name  = "cluster.name"
            value = "elk-cluster"
          }

          env {
            name  = "node.name"
            value = "elasticsearch-0"
          }

          env {
            name  = "discovery.type"
            value = "single-node"
          }

          env {
            name  = "ES_JAVA_OPTS"
            value = "-Xms1g -Xmx1g"
          }

          volume_mount {
            name       = "elasticsearch-data"
            mount_path = "/usr/share/elasticsearch/data"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "elasticsearch-data"
      }

      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "10Gi"
          }
        }
        storage_class_name = "standard"
      }
    }
  }
}

# Elasticsearch Service
resource "kubernetes_service" "elasticsearch" {
  metadata {
    name      = "elasticsearch"
    namespace = kubernetes_namespace.elk.metadata[0].name
  }

  spec {
    selector = {
      app = "elasticsearch"
    }

    port {
      name        = "rest"
      port        = 9200
      target_port = 9200
    }

    port {
      name        = "inter-node"
      port        = 9300
      target_port = 9300
    }

    type = "ClusterIP"
  }
}

# Kibana Deployment
resource "kubernetes_deployment" "kibana" {
  metadata {
    name      = "kibana"
    namespace = kubernetes_namespace.elk.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "kibana"
      }
    }

    template {
      metadata {
        labels = {
          app = "kibana"
        }
      }

      spec {
        container {
          name  = "kibana"
          image = "docker.elastic.co/kibana/kibana:7.15.0"

          port {
            container_port = 5601
          }

          resources {
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
            requests = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          env {
            name  = "ELASTICSEARCH_URL"
            value = "http://elasticsearch:9200"
          }

          env {
            name  = "ELASTICSEARCH_HOSTS"
            value = "http://elasticsearch:9200"
          }
        }
      }
    }
  }
}

# Kibana Service
resource "kubernetes_service" "kibana" {
  metadata {
    name      = "kibana"
    namespace = kubernetes_namespace.elk.metadata[0].name
  }

  spec {
    selector = {
      app = "kibana"
    }

    port {
      port        = 5601
      target_port = 5601
    }

    type = "ClusterIP"
  }
}

# Logstash ConfigMap
resource "kubernetes_config_map" "logstash_config" {
  metadata {
    name      = "logstash-config"
    namespace = kubernetes_namespace.elk.metadata[0].name
  }

  data = {
    "logstash.conf" = <<-EOF
      input {
        http {
          port => 8080
        }
      }
      
      filter {
        json {
          source => "message"
        }
      }
      
      output {
        elasticsearch {
          hosts => ["elasticsearch:9200"]
          index => "app-logs-%{+YYYY.MM.dd}"
        }
      }
    EOF
  }
}

# Logstash Deployment
resource "kubernetes_deployment" "logstash" {
  metadata {
    name      = "logstash"
    namespace = kubernetes_namespace.elk.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "logstash"
      }
    }

    template {
      metadata {
        labels = {
          app = "logstash"
        }
      }

      spec {
        container {
          name  = "logstash"
          image = "docker.elastic.co/logstash/logstash:7.15.0"

          port {
            container_port = 8080
            name           = "http"
          }

          resources {
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
            requests = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          volume_mount {
            name       = "config-volume"
            mount_path = "/usr/share/logstash/pipeline"
          }
        }

                  volume {
          name = "config-volume"
          config_map {
            name = "logstash-config"
            items {
              key  = "logstash.conf"
              path = "logstash.conf"
            }
          }
        }
      }
    }
  }
}

# Logstash Service
resource "kubernetes_service" "logstash" {
  metadata {
    name      = "logstash"
    namespace = kubernetes_namespace.elk.metadata[0].name
  }

  spec {
    selector = {
      app = "logstash"
    }

    port {
      port        = 8080
      target_port = 8080
    }

    type = "ClusterIP"
  }
}

# Filebeat ConfigMap
resource "kubernetes_config_map" "filebeat_config" {
  metadata {
    name      = "filebeat-config"
    namespace = kubernetes_namespace.elk.metadata[0].name
  }

  data = {
    "filebeat.yml" = <<-EOF
      filebeat.inputs:
      - type: container
        paths:
          - /var/log/containers/*.log
        processors:
          - add_kubernetes_metadata:
              host: ${ENV_HOSTNAME}
              in_cluster: true
      
      output.elasticsearch:
        hosts: ["elasticsearch:9200"]
    EOF
  }
}

# Filebeat DaemonSet
resource "kubernetes_daemonset" "filebeat" {
  metadata {
    name      = "filebeat"
    namespace = kubernetes_namespace.elk.metadata[0].name
  }

  spec {
    selector {
      match_labels = {
        app = "filebeat"
      }
    }

    template {
      metadata {
        labels = {
          app = "filebeat"
        }
      }

      spec {
        service_account_name = "filebeat"
        
        container {
          name  = "filebeat"
          image = "docker.elastic.co/beats/filebeat:7.15.0"
          
          args = [
            "-c", "/etc/filebeat.yml",
            "-e",
          ]
          
          env {
            name = "ENV_HOSTNAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }
          
          security_context {
            run_as_user = 0
          }
          
          resources {
            limits = {
              memory = "200Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "100Mi"
            }
          }
          
          volume_mount {
            name       = "config"
            mount_path = "/etc/filebeat.yml"
            sub_path   = "filebeat.yml"
            read_only  = true
          }
          
          volume_mount {
            name       = "data"
            mount_path = "/usr/share/filebeat/data"
          }
          
          volume_mount {
            name       = "varlibdockercontainers"
            mount_path = "/var/lib/docker/containers"
            read_only  = true
          }
          
          volume_mount {
            name       = "varlog"
            mount_path = "/var/log"
            read_only  = true
          }
        }
        
        volume {
          name = "config"
          config_map {
            name = "filebeat-config"
          }
        }
        
        volume {
          name = "data"
          empty_dir {}
        }
        
        volume {
          name = "varlibdockercontainers"
          host_path {
            path = "/var/lib/docker/containers"
          }
        }
        
        volume {
          name = "varlog"
          host_path {
            path = "/var/log"
          }
        }
      }
    }
  }
}

# Filebeat ServiceAccount
resource "kubernetes_service_account" "filebeat" {
  metadata {
    name      = "filebeat"
    namespace = kubernetes_namespace.elk.metadata[0].name
  }
}

# Filebeat ClusterRole
resource "kubernetes_cluster_role" "filebeat" {
  metadata {
    name = "filebeat"
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces", "pods", "nodes"]
    verbs      = ["get", "list", "watch"]
  }
}

# Filebeat ClusterRoleBinding
resource "kubernetes_cluster_role_binding" "filebeat" {
  metadata {
    name = "filebeat"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "filebeat"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "filebeat"
    namespace = kubernetes_namespace.elk.metadata[0].name
  }
}

# Kibana Ingress
resource "kubernetes_ingress_v1" "kibana" {
  metadata {
    name      = "kibana"
    namespace = kubernetes_namespace.elk.metadata[0].name
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
              name = "kibana"
              port {
                number = 5601
              }
            }
          }
        }
      }
    }
  }
}
