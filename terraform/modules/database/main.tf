# terraform/modules/database/main.tf
resource "google_compute_global_address" "private_ip_address" {
  name          = "${var.environment}-db-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.vpc_id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = var.vpc_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

resource "google_sql_database_instance" "postgres" {
  name             = "${var.environment}-${var.db_instance_name}"
  database_version = "POSTGRES_13"
  region           = var.region
  
  depends_on = [
    google_service_networking_connection.private_vpc_connection
  ]
  
  settings {
    tier = var.environment == "production" ? "db-custom-2-7680" : "db-f1-micro"
    
    ip_configuration {
      ipv4_enabled    = false
      private_network = var.vpc_id
    }
    
    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"
      point_in_time_recovery_enabled = var.environment == "production" ? true : false
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
  }

  deletion_protection = var.environment == "production" ? true : false
}

resource "google_sql_database" "database" {
  name     = var.db_name
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_user" "app_user" {
  name     = var.db_user
  instance = google_sql_database_instance.postgres.name
  password = var.db_password
}

resource "google_secret_manager_secret" "db_connection" {
  secret_id = "${var.environment}-db-connection"
  
  replication {
    automatic = true
  }

  labels = {
    environment = var.environment
  }
}

# Store the database connection string in Secret Manager
resource "google_secret_manager_secret_version" "db_connection_version" {
  secret      = google_secret_manager_secret.db_connection.id
  secret_data = "postgresql://${google_sql_user.app_user.name}:${var.db_password}@${google_sql_database_instance.postgres.private_ip_address}:5432/${google_sql_database.database.name}"
}
