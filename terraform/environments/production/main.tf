# terraform/environments/production/main.tf
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

locals {
  environment = "production"
}

# Enable required APIs
module "apis" {
  source = "../../modules/apis"

  project_id = var.project_id
}

module "networking" {
  source = "../../modules/networking"

  project_id   = var.project_id
  region       = var.region
  environment  = local.environment
  network_name = "vpc"
  subnet_cidr  = "10.1.0.0/20"

  depends_on = [module.apis]
}

module "database" {
  source = "../../modules/database"

  project_id       = var.project_id
  region           = var.region
  environment      = local.environment
  vpc_id           = module.networking.vpc_id
  db_instance_name = "${var.project_prefix}-postgres"
  db_password      = var.db_password

  depends_on = [module.networking]
}

module "kubernetes" {
  source = "../../modules/kubernetes"

  project_id       = var.project_id
  region           = var.region
  environment      = local.environment
  vpc_id           = module.networking.vpc_id
  subnet_id        = module.networking.subnet_id
  cluster_name     = "${var.project_prefix}-gke-cluster"
  node_count       = 4
  machine_type     = "e2-standard-2"
  node_preemptible = false

  depends_on = [module.networking]
}

module "messaging" {
  source = "../../modules/messaging"

  project_id  = var.project_id
  environment = local.environment
  topic_name  = "${var.project_prefix}-app-topic"

  depends_on = [module.apis]
}

module "logging" {
  source = "../../modules/logging"

  project_id           = var.project_id
  environment          = local.environment
  cluster_name         = module.kubernetes.cluster_name
  elasticsearch_version = "7.15.0"
  kibana_version       = "7.15.0"
  logstash_version     = "7.15.0"
  elasticsearch_disk_size = 30

  depends_on = [module.kubernetes]
}

# Deploy application Kubernetes resources
resource "kubernetes_namespace" "app" {
  metadata {
    name = local.environment
  }

  depends_on = [module.kubernetes]
}

# Create ConfigMap for the application
resource "kubernetes_config_map" "app_config" {
  metadata {
    name      = "app-config"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  data = {
    "CONFIG_ENV" = local.environment
    "LOG_LEVEL"  = "info"
  }
}

# Create Secret for the application
resource "kubernetes_secret" "app_secrets" {
  metadata {
    name      = "app-secrets"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  data = {
    "DB_SECRET_NAME" = module.database.connection_secret_id
    "PUBSUB_TOPIC"   = module.messaging.topic_name
    "LOGSTASH_HOST"  = "http://logstash.${module.logging.namespace}.svc.cluster.local:8080"
  }
}
