# terraform/environments/production/bastion.tf
resource "google_compute_instance" "bastion" {
  name         = "${local.environment}-${var.project_prefix}-bastion"
  machine_type = "e2-micro"
  zone         = var.zone
  project      = var.project_id

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 10
    }
  }

  network_interface {
    network    = module.networking.vpc_name
    subnetwork = module.networking.subnet_name

    access_config {
      // Ephemeral public IP
    }
  }

  service_account {
    email  = module.kubernetes.gke_service_account_email
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
    apt-get install -y google-oslogin kubectl google-cloud-sdk-gke-gcloud-auth-plugin
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
    
    # Configure kubectl for the GKE cluster
    gcloud container clusters get-credentials ${module.kubernetes.cluster_name} --zone ${var.region} --project ${var.project_id}
    
    # Install monitoring agent
    curl -sSO https://dl.google.com/cloudagents/add-monitoring-agent-repo.sh
    bash add-monitoring-agent-repo.sh
    apt-get update
    apt-get install -y stackdriver-agent
    service stackdriver-agent start
  EOF

  tags = ["bastion"]

  depends_on = [module.kubernetes]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${local.environment}-${var.project_prefix}-allow-ssh"
  network = module.networking.vpc_name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.bastion_allowed_cidr]
  target_tags   = ["bastion"]
}

output "bastion_public_ip" {
  value       = google_compute_instance.bastion.network_interface[0].access_config[0].nat_ip
  description = "The public IP address of the bastion host"
}
