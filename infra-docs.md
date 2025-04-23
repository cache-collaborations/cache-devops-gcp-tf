# Infrastructure Documentation

This document provides detailed information about the infrastructure setup, focusing on IAM, secret management, audit logging, and SOC 2 compliance.

## IAM Roles and Policies

The infrastructure follows the principle of least privilege, providing each service account with only the permissions necessary to perform its functions.

### Service Accounts

1. **GKE Node Service Account (`cache-gke-sa@`):**
   - Used by GKE nodes to interact with GCP services
   - Permissions:
     - `roles/logging.logWriter`
     - `roles/monitoring.metricWriter`
     - `roles/monitoring.viewer`
     - `roles/storage.objectViewer`
     - `roles/artifactregistry.reader`

2. **Application Service Account (`cache-app-sa@`):**
   - Used by the application to access GCP services
   - Permissions:
     - `roles/secretmanager.secretAccessor`
     - `roles/pubsub.publisher`
     - `roles/pubsub.subscriber`

3. **GitHub Actions Service Account:**
   - Used for CI/CD from GitHub
   - Permissions:
     - `roles/container.developer`
     - `roles/storage.admin`
     - `roles/artifactregistry.admin`

### Workload Identity

The infrastructure uses GKE Workload Identity to securely connect Kubernetes service accounts to GCP service accounts:

- Production namespace: `serviceAccount:${PROJECT_ID}.svc.id.goog[production/app]`
- Staging namespace: `serviceAccount:${PROJECT_ID}.svc.id.goog[staging/app]`

This allows Kubernetes pods to access GCP services without using service account keys, improving security.

### IAM Best Practices Implemented

1. **Principle of Least Privilege:** Each service account has only the permissions it needs
2. **Service Account Separation:** Different service accounts for different components
3. **Avoid Service Account Keys:** Using Workload Identity instead of downloaded keys
4. **Regular Audit:** IAM policies should be regularly reviewed and updated

## Secret Management

Secrets are stored and managed in Google Secret Manager, which provides:

- Encryption at rest and in transit
- Fine-grained access control
- Versioning
- Audit logging

### Secrets Stored

1. **Database Password (`cache-db-password`):**
   - Stores the PostgreSQL user password
   - Accessed by the application service account

2. **Database Connection String (`cache-db-connection`):**
   - Stores the complete PostgreSQL connection string
   - Format: `postgresql://username:password@host:port/database`
   - Accessed by the application service account

### Secret Access in Kubernetes

1. Kubernetes pods access secrets using the GCP service account associated via Workload Identity
2. The Python application reads secrets directly from Secret Manager at runtime using the google-cloud-secret-manager library
3. Secret names are referenced in Kubernetes Secrets, but the actual values are not stored in Kubernetes

## Audit Logging and Monitoring

### GCP Audit Logging

Audit logging is enabled for all relevant services:

1. **Admin Activity Logs:** 
   - Automatically enabled and cannot be disabled
   - Tracks administrative actions (e.g., IAM changes, resource creation)

2. **Data Access Logs:**
   - Enabled for Secret Manager, Cloud SQL, and GKE
   - Tracks data access and modifications

3. **System Event Logs:**
   - Tracks GCP system events
   - Useful for troubleshooting and forensics

### Bastion Host Audit Logging

The bastion host has enhanced audit logging:

1. **OS Login:** Enabled to manage SSH access with IAM
2. **auditd:** Configured to log:
   - Authentication events
   - File changes to critical files (passwd, shadow, etc.)
   - Login/logout events
3. **Stackdriver Agent:** Forwards logs to Cloud Logging

### Network Logging

1. **NAT Logging:** Enabled for error logging
2. **VPC Flow Logs:** Can be enabled to track network traffic
3. **Firewall Rule Logging:** Can be enabled to audit firewall rule matches

### Application Logging

1. **Application Logs:** Sent to Cloud Logging and ELK stack
2. **Structured Logging:** JSON format with context information
3. **Log Levels:** Configurable via environment variables (using Python's logging module)

### ELK Stack Integration

The ELK stack provides:

1. **Centralized Logging:** All application logs in one place
2. **Log Analysis:** Kibana dashboards for visualization
3. **Log Retention:** Configurable retention periods
4. **Alerting:** Can be set up for specific log patterns

## SOC 2 Alignment

The infrastructure is designed with SOC 2 compliance in mind, addressing key trust service criteria:

### Security

1. **Network Segmentation:**
   - VPC with separate subnets for staging and production
   - GKE private cluster with limited external access
   - Network policies restricting pod-to-pod communication

2. **Access Control:**
   - Least privilege IAM roles
   - Workload Identity for secure service account access
   - OS Login for bastion host access

3. **Data Encryption:**
   - Encryption at rest for Cloud SQL
   - Encryption at rest for Secret Manager
   - TLS for all communications

4. **Secret Management:**
   - Centralized secret storage in Secret Manager
   - No hardcoded secrets in the application or infrastructure

### Availability

1. **High Availability:**
   - Multi-node GKE cluster
   - Cloud SQL with high availability option
   - Horizontal Pod Autoscaling

2. **Monitoring and Alerting:**
   - Cloud Monitoring integration
   - ELK stack for log monitoring
   - Health check endpoints

3. **Backup and Recovery:**
   - Cloud SQL automated backups
   - Point-in-time recovery
   - Stateless application design

### Processing Integrity

1. **CI/CD Pipeline:**
   - Automated testing with pytest
   - Deployment approval process
   - Environment separation

2. **Change Management:**
   - Infrastructure as Code (Terraform)
   - Version control
   - Peer reviews via Pull Requests

3. **Input Validation:**
   - API validations
   - Database constraints

### Confidentiality

1. **Data Classification:**
   - Sensitive data identified and protected
   - Access restricted based on need-to-know

2. **Secure Communication:**
   - TLS encryption
   - Private networking where possible

3. **Data Access Control:**
   - Fine-grained IAM permissions
   - Audit logging for data access

### Privacy

1. **Data Minimization:**
   - Only necessary data is collected and stored
   - Clear purpose for all data collection

2. **Access Control:**
   - Restricted access to production environment
   - Role-based access control

## Audit Readiness Checklist

- [x] Infrastructure provisioned with Terraform (documentable, repeatable)
- [x] IAM roles follow least privilege principle
- [x] Secrets stored in Secret Manager (not in code or Kubernetes secrets)
- [x] Audit logging enabled for critical services
- [x] Network segmentation implemented
- [x] Encryption at rest and in transit enabled
- [x] CI/CD pipeline with security controls
- [x] Bastion host with enhanced logging
- [x] Monitoring and alerting capabilities
- [x] Backup and recovery procedures
- [x] Documentation of all infrastructure components
