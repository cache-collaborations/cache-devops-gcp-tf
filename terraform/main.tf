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

# Enable required APIs
resource "google_project_service" "gcp_services" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
    "secretmanager.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbuild.googleapis.com"
  ])
  project = var.project_id
  service = each.value

  disable_dependent_services = true
  disable_on_destroy         = false
}

# VPC Network
resource "google_compute_network" "vpc" {
  name                    = "${var.project_prefix}-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.gcp_services]
}

# Staging Subnet
resource "google_compute_subnetwork" "staging_subnet" {
  name          = "${var.project_prefix}-staging-subnet"
  ip_cidr_range = "10.0.0.0/20"
  region        = var.region
  network       = google_compute_network.vpc.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.16.0.0/14"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.20.0.0/20"
  }

  private_ip_google_access = true
}

# Production Subnet
resource "google_compute_subnetwork" "prod_subnet" {
  name          = "${var.project_prefix}-prod-subnet"
  ip_cidr_range = "10.1.0.0/20"
  region        = var.region
  network       = google_compute_network.vpc.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.24.0.0/14"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.28.0.0/20"
  }

  private_ip_google_access = true
}

# Router for NAT gateway
resource "google_compute_router" "router" {
  name    = "${var.project_prefix}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

# NAT gateway
resource "google_compute_router_nat" "nat" {
  name                               = "${var.project_prefix}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall rule to allow internal communication
resource "google_compute_firewall" "internal" {
  name    = "${var.project_prefix}-allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  source_ranges = ["10.0.0.0/20", "10.1.0.0/20", "10.16.0.0/14", "10.20.0.0/20", "10.24.0.0/14", "10.28.0.0/20"]
}

# GKE Cluster
resource "google_container_cluster" "primary" {
  name     = "${var.project_prefix}-gke-cluster"
  location = var.region

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.prod_subnet.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Enable Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Enable network policy
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # Enable private cluster
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Enable master authorized networks
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "all"
    }
  }

  # Enable shielded nodes
  node_config {
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  # Enable logging and monitoring
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"
  
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }
}

# Node pool for production
resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.project_prefix}-prod-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = 2

  node_config {
    preemptible  = false
    machine_type = "e2-standard-2"

    service_account = google_service_account.gke_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      env = "production"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Enable workload identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

# Node pool for staging
resource "google_container_node_pool" "staging_nodes" {
  name       = "${var.project_prefix}-staging-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = 1

  node_config {
    preemptible  = true
    machine_type = "e2-standard-2"

    service_account = google_service_account.gke_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      env = "staging"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Enable workload identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

# Service account for GKE nodes
resource "google_service_account" "gke_sa" {
  account_id   = "${var.project_prefix}-gke-sa"
  display_name = "GKE Service Account"
}

# Grant necessary roles to GKE service account
resource "google_project_iam_member" "gke_sa_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/storage.objectViewer",
    "roles/artifactregistry.reader"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

# PostgreSQL Cloud SQL instance
resource "google_compute_global_address" "private_ip_address" {
  name          = "${var.project_prefix}-db-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

resource "google_sql_database_instance" "postgres" {
  name             = "${var.project_prefix}-postgres"
  database_version = "POSTGRES_13"
  region           = var.region
  
  depends_on = [
    google_service_networking_connection.private_vpc_connection
  ]
  
  settings {
    tier = "db-f1-micro"
    
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
    }
    
    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"
      point_in_time_recovery_enabled = true
    }
    
    maintenance_window {
      day          = 7
      hour         = 3
      update_track = "stable"
    }
    
    database_flags {
      name  = "log_connections"
      value = "on"
    }
    
    database_flags {
      name  = "log_disconnections"
      value = "on"
    }
    
    database_flags {
      name  = "log_statement"
      value = "ddl"
    }
  }

  deletion_protection = true # Set to true for production
}

resource "google_sql_database" "database" {
  name     = "app-database"
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_user" "app_user" {
  name     = "app-user"
  instance = google_sql_database_instance.postgres.name
  password = var.db_password
}

# Pub/Sub
resource "google_pubsub_topic" "app_topic" {
  name = "${var.project_prefix}-app-topic"
}

resource "google_pubsub_subscription" "app_subscription" {
  name  = "${var.project_prefix}-app-subscription"
  topic = google_pubsub_topic.app_topic.name

  ack_deadline_seconds = 20

  message_retention_duration = "604800s" # 7 days

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  expiration_policy {
    ttl = "2592000s" # 30 days
  }
}

# Secret Manager for storing sensitive information
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.project_prefix}-db-password"
  
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "db_password_version" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = var.db_password
}

resource "google_secret_manager_secret" "db_connection" {
  secret_id = "${var.project_prefix}-db-connection"
  
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "db_connection_version" {
  secret      = google_secret_manager_secret.db_connection.id
  secret_data = "postgresql://${google_sql_user.app_user.name}:${var.db_password}@${google_sql_database_instance.postgres.private_ip_address}:5432/${google_sql_database.database.name}"
}

# Service account for the application
resource "google_service_account" "app_sa" {
  account_id   = "${var.project_prefix}-app-sa"
  display_name = "Application Service Account"
}

# Grant necessary permissions to the application service account
resource "google_project_iam_member" "app_sa_roles" {
  for_each = toset([
    "roles/secretmanager.secretAccessor",
    "roles/pubsub.publisher",
    "roles/pubsub.subscriber"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.app_sa.email}"
}

# Allow GKE service account to impersonate app service account
resource "google_service_account_iam_binding" "gke_workload_identity_binding" {
  service_account_id = google_service_account.app_sa.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[production/app]",
    "serviceAccount:${var.project_id}.svc.id.goog[staging/app]"
  ]
}

# Bastion host to simulate VPN access
resource "google_compute_instance" "bastion" {
  name         = "${var.project_prefix}-bastion"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network    = google_compute_network.vpc.name
    subnetwork = google_compute_subnetwork.prod_subnet.name

    access_config {
      // Ephemeral public IP
    }
  }

  service_account {
    email  = google_service_account.gke_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  # Enable OS Login
  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y google-oslogin
    systemctl enable google-oslogin
    systemctl start google-oslogin
    
    # Setup audit logging
    apt-get install -y auditd
    cat > /etc/audit/rules.d/audit.rules << 'AUDITEOF'
    -w /var/log/auth.log -p rwa -k auth_log
    -w /etc/passwd -p rwa -k passwd_changes
    -w /etc/group -p rwa -k group_changes
    -w /etc/shadow -p rwa -k shadow_changes
    -w /etc/sudoers -p rwa -k sudoers_changes
    -w /var/log/wtmp -p wa -k wtmp_log
    -w /var/log/btmp -p wa -k btmp_log
    AUDITEOF
    service auditd restart
    
    # Install Stackdriver logging agent
    curl -sSO https://dl.google.com/cloudagents/add-logging-agent-repo.sh
    bash add-logging-agent-repo.sh
    apt-get update
    apt-get install -y google-fluentd
    service google-fluentd start
  EOF
}

# Firewall rule to allow SSH access to the bastion host
resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.project_prefix}-allow-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.bastion_allowed_cidr]
  target_tags   = ["bastion"]
}

# Output the GKE cluster endpoint
output "gke_cluster_endpoint" {
  value = google_container_cluster.primary.endpoint
}

# Output the Cloud SQL private IP
output "cloudsql_private_ip" {
  value = google_sql_database_instance.postgres.private_ip_address
}

# Output the bastion host public IP
output "bastion_public_ip" {
  value = google_compute_instance.bastion.network_interface[0].access_config[0].nat_ip
}
