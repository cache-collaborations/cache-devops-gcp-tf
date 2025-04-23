# Cache: DevOps Engineer Take-Home Assessment

This repository contains a secure, production-grade infrastructure setup on Google Cloud Platform (GCP) for deploying a Python Flask application that integrates with Pub/Sub, PostgreSQL, and ELK Stack, with CI/CD support.

## Architecture

The infrastructure follows industry best practices and SOC 2 compliance requirements with separate staging and production environments:

- **Networking**: VPC with separate subnets for staging and production
- **Compute**: GKE cluster with environment namespaces and appropriate node configurations
- **Database**: Cloud SQL PostgreSQL with private networking
- **Messaging**: Pub/Sub topics and subscriptions
- **Logging**: ELK Stack (Elasticsearch, Logstash, Kibana)
- **Security**: Secret Manager, IAM with least privilege, Workload Identity
- **CI/CD**: GitHub Actions and Cloud Build pipelines

### Architecture Diagram

```
+---------------------------------------------------------------------+
|                          Google Cloud Platform                       |
|                                                                      |
|  +----------------------+        +-----------------------------+     |
|  |    VPC Network       |        |      Secret Manager         |     |
|  |                      |        |  (DB, PubSub credentials)   |     |
|  +----------------------+        +-----------------------------+     |
|         |                                     |                      |
|         v                                     |                      |
|  +------------------------------------------------------+            |
|  |                                                      |            |
|  |  +-------------+            +-------------+          |            |
|  |  | Production  |            |  Staging    |          |            |
|  |  |  Subnet     |            |  Subnet     |          |            |
|  |  +-------------+            +-------------+          |            |
|  |        |                          |                  |            |
|  |        v                          v                  |            |
|  |  +---------------------------------------------+     |            |
|  |  |               GKE Cluster                   |     |            |
|  |  |                                             |     |            |
|  |  |  +------------+        +------------+       |<----+            |
|  |  |  | Production |        | Staging    |       |                  |
|  |  |  | Namespace  |        | Namespace  |       |                  |
|  |  |  +------------+        +------------+       |                  |
|  |  |        |                    |               |                  |
|  |  +--------|--------------------|---------------+                  |
|  |           |                    |                                  |
|  +-----------|--------------------|----------------------------------+
|              |                    |                                  |
|              v                    v                                  |
|  +----------------+  +----------------+  +------------------------+  |
|  |   Cloud SQL    |  |    Pub/Sub     |  |       ELK Stack        |  |
|  | (PostgreSQL)   |  |                |  | (Logs & Monitoring)    |  |
|  +----------------+  +----------------+  +------------------------+  |
|                                                                      |
+----------------------------------------------------------------------+
        |                                              ^
        |                                              |
        v                                              |
+------------------+                     +------------------------+
| GitHub Repository|-------------------->|     CI/CD Pipeline     |
|                  |                     | (GitHub Actions or     |
|                  |                     |    Cloud Build)        |
+------------------+                     +------------------------+
```

## Repository Structure

```
cache-devops-assessment/
├── .github/
│   └── workflows/
│       └── ci-cd.yml            # GitHub Actions workflow
│
├── terraform/
│   ├── modules/                 # Reusable Terraform modules
│   │   ├── apis/                # API enablement
│   │   ├── networking/          # VPC, subnets, firewalls
│   │   ├── kubernetes/          # GKE cluster configuration
│   │   ├── database/            # PostgreSQL configuration
│   │   ├── messaging/           # Pub/Sub configuration
│   │   └── logging/             # ELK stack deployment
│   │
│   ├── environments/            # Environment-specific configurations
│   │   ├── staging/             # Staging environment
│   │   │   ├── main.tf          # Main configuration
│   │   │   ├── variables.tf     # Variables
│   │   │   ├── outputs.tf       # Outputs
│   │   │   ├── secrets.tf       # Secret management
│   │   │   ├── kubernetes.tf    # Kubernetes resources
│   │   │   └── terraform.tfvars.example  # Example variables
│   │   │
│   │   └── production/          # Production environment
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       ├── secrets.tf
│   │       ├── kubernetes.tf
│   │       └── terraform.tfvars.example
│
├── app/
│   ├── app.py                   # Flask application
│   ├── test_app.py              # Unit tests
│   ├── Dockerfile               # Container configuration
│
│
├── cloudbuild.yaml              # Cloud Build configuration
├── README.md                    # This file
└── infra-docs.md                # Infrastructure documentation
└── requirements.txt             # Python dependencies
```

## Prerequisites

- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) (v350.0.0+)
- [Terraform](https://www.terraform.io/downloads.html) (v1.0.0+)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) (v1.20.0+)
- [Python](https://www.python.org/downloads/) (v3.9+)
- [Docker](https://docs.docker.com/get-docker/) (v20.10.0+)
- GCP Account with Owner or Editor permissions

## Setup Instructions

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/cache-devops-assessment.git
cd cache-devops-assessment
```

### 2. GCP Project Configuration

```bash
# Login to Google Cloud
gcloud auth login

# Create a new project (optional)
gcloud projects create YOUR_PROJECT_ID --name="Cache DevOps Assessment"

# Set the project ID
gcloud config set project YOUR_PROJECT_ID

# Enable billing for the project (required for resource creation)
gcloud billing projects link YOUR_PROJECT_ID --billing-account=YOUR_BILLING_ACCOUNT_ID
```

### 3. Enable Required APIs

```bash
gcloud services enable compute.googleapis.com \
    container.googleapis.com \
    servicenetworking.googleapis.com \
    sqladmin.googleapis.com \
    secretmanager.googleapis.com \
    pubsub.googleapis.com \
    cloudbuild.googleapis.com \
    logging.googleapis.com \
    monitoring.googleapis.com \
    cloudresourcemanager.googleapis.com
```

### 4. Create Artifact Registry Repository

```bash
gcloud artifacts repositories create app-registry \
    --repository-format=docker \
    --location=us-central1 \
    --description="Docker repository for app images"
```

### 5. Build and Push the Application

```bash
# Configure Docker for Artifact Registry
gcloud auth configure-docker us-central1-docker.pkg.dev

# Build the container image
docker build -t us-central1-docker.pkg.dev/YOUR_PROJECT_ID/app-registry/app:latest app/

# Push the image to Artifact Registry
docker push us-central1-docker.pkg.dev/YOUR_PROJECT_ID/app-registry/app:latest

# Tag the image for staging
docker tag us-central1-docker.pkg.dev/YOUR_PROJECT_ID/app-registry/app:latest \
    us-central1-docker.pkg.dev/YOUR_PROJECT_ID/app-registry/app:staging

# Push the staging tag
docker push us-central1-docker.pkg.dev/YOUR_PROJECT_ID/app-registry/app:staging
```

### 6. Initialize and Apply Terraform for Staging Environment

```bash
cd terraform/environments/staging

# Create terraform.tfvars file from example
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your project-specific values
# Do NOT include sensitive values in this file
vi terraform.tfvars

# Set environment variables for sensitive values
export TF_VAR_db_password="your-secure-database-password"
export TF_VAR_api_key="your-api-key"

# Initialize Terraform
terraform init

# Validate the configuration
terraform validate

# Plan the deployment
terraform plan -out=tfplan

# Apply the configuration
terraform apply tfplan
```

### 7. Set up Cloud Build

```bash
# Get the Cloud Build service account email
PROJECT_ID=YOUR_PROJECT_ID
SERVICE_ACCOUNT=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')@cloudbuild.gserviceaccount.com

# Grant the necessary role for GKE access
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:$SERVICE_ACCOUNT \
    --role=roles/container.developer

# Grant artifact registry access
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:$SERVICE_ACCOUNT \
    --role=roles/artifactregistry.admin

# Grant Secret Manager access
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:$SERVICE_ACCOUNT \
    --role=roles/secretmanager.secretAccessor

# Trigger a Cloud Build pipeline
gcloud builds submit --config=cloudbuild.yaml \
    --substitutions=_NAMESPACE=staging,_TAG=staging
```

### 8. Set up GitHub Actions

```bash
# Create a service account for GitHub Actions
gcloud iam service-accounts create github-actions \
    --display-name="GitHub Actions"

# Grant necessary permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:github-actions@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/container.developer"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:github-actions@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/artifactregistry.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:github-actions@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"

# Create and download service account key
gcloud iam service-accounts keys create github-actions-key.json \
    --iam-account=github-actions@$PROJECT_ID.iam.gserviceaccount.com

# Base64 encode the key (for GitHub secrets)
cat github-actions-key.json | base64 -w 0
```

Add the following secrets to your GitHub repository:
- `GCP_PROJECT_ID`: Your GCP project ID
- `GCP_SA_KEY`: The base64-encoded content of the github-actions-key.json file

### 9. Deploy to Production Environment

```bash
cd ../production

# Create terraform.tfvars file from example
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your project-specific values
vi terraform.tfvars

# Use the same sensitive environment variables as before
# Initialize Terraform
terraform init

# Validate the configuration
terraform validate

# Plan the deployment
terraform plan -out=tfplan

# Apply the configuration
terraform apply tfplan
```

### 10. Access the Deployed Resources

```bash
# Configure kubectl for the staging environment
gcloud container clusters get-credentials staging-cache-gke-cluster --region us-central1 --project $PROJECT_ID

# Get the application endpoint in staging
kubectl -n staging get ingress app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Get Kibana endpoint in staging
kubectl -n staging-elk get ingress kibana -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Switch to production environment
gcloud container clusters get-credentials production-cache-gke-cluster --region us-central1 --project $PROJECT_ID

# Get the application endpoint in production
kubectl -n production get ingress app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Get Kibana endpoint in production
kubectl -n production-elk get ingress kibana -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### 11. Testing the Application

The application provides the following endpoints:

- `GET /health` - Health check endpoint
- `POST /api/events` - Create a new event (requires JSON body with `message` field)
- `GET /api/events` - List all events

Example:

```bash
# Health check
curl http://<app-ingress-ip>/health

# Create an event
curl -X POST http://<app-ingress-ip>/api/events \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello, world!"}'

# Get all events
curl http://<app-ingress-ip>/api/events
```

## Security Features

This implementation includes several security best practices:

1. **Network Segmentation**: Separate VPC networks for staging and production environments.
2. **Secret Management**: Secure handling of credentials using Google Secret Manager.
3. **Least Privilege**: IAM roles following the principle of least privilege.
4. **Workload Identity**: Secure service account access without key files.
5. **Private Cluster**: GKE clusters with private nodes.
6. **Audit Logging**: Comprehensive logging for all components.
7. **TLS**: Secure communication with TLS.
8. **Container Security**: Non-root container execution.
9. **Service Isolation**: Namespace separation for different environments.

For more details, see [infra-docs.md](infra-docs.md).

## Cleaning Up

To avoid ongoing charges, clean up the resources when no longer needed:

```bash
# Destroy production environment
cd terraform/environments/production
terraform destroy

# Destroy staging environment
cd ../staging
terraform destroy

# Delete Artifact Registry repository
gcloud artifacts repositories delete app-registry --location=us-central1

# Delete the project (optional)
gcloud projects delete YOUR_PROJECT_ID
```

## Troubleshooting

### Common Issues

1. **API not enabled**: Ensure all required APIs are enabled before applying Terraform.

2. **Permission denied**: Verify that your account has the necessary permissions.

3. **Secret not found**: Check that secrets exist in Secret Manager and are accessible by the service accounts.

4. **Connection issues**: Verify network configuration and firewall rules.

### Debugging

1. **Check GKE pod logs**:
   ```bash
   kubectl -n <namespace> logs deployment/app
   ```

2. **Examine Cloud Build logs**:
   ```bash
   gcloud builds list
   gcloud builds log <build-id>
   ```

3. **View Stackdriver logs**:
   ```bash
   gcloud logging read "resource.type=k8s_container AND resource.labels.namespace_name=<namespace> AND resource.labels.container_name=app"
   ```

4. **Access Kibana dashboard** for detailed application logs:
   Open `http://<kibana-ingress-ip>:5601` in your browser