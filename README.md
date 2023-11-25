# Automatic1111-on-GKE-Autopilot
Effortless AI Art: Deploying Stable Diffusion with Automatic1111 on GKE Autopilot

Creating a comprehensive and user-friendly `README.md` file for your GitHub repository is essential to guide users through deploying a GPU-based container app on GKE Autopilot. Here's a suggested structure for your `README.md`:

---

# Deploying GPU-Based Container App on GKE Autopilot

## Overview
This guide provides detailed instructions for deploying a GPU-based container application on Google Kubernetes Engine (GKE) Autopilot. The process involves creating an Autopilot GKE cluster, building a Docker image with multi-stage builds, and deploying the application using Kubernetes configurations.

## Prerequisites
- Google Cloud Account
- gcloud CLI installed and configured
- Docker installed

## Step 1: Create GKE Autopilot Cluster
1. Navigate to Google Cloud Console.
2. Create a new GKE Autopilot cluster.

## Step 2: Enable Cloud Run for GKE
Run the following commands to enable Cloud Run:
```bash
gcloud container fleet cloudrun enable --project=PROJECT_ID
gcloud container fleet cloudrun apply --gke-cluster=CLUSTER_LOCATION/CLUSTER_NAME
```

## Step 3: Prepare Local Directory and Dockerfile
Create a local directory and include the provided Dockerfile which utilizes multi-stage builds to reduce the final image size.

## Dockerfile
```Dockerfile
# Use multi-stage builds to reduce final image size
FROM nvidia/cuda:12.0.0-cudnn8-runtime-ubuntu22.04 as builder

# Set non-interactive frontend
ENV DEBIAN_FRONTEND=noninteractive 

# Install dependencies in a single RUN command to reduce layers
RUN apt-get update -y && apt-get install -y \
    wget bzip2 unzip libgl1-mesa-glx libglib2.0-0 git \
    libgoogle-perftools4 libtcmalloc-minimal4 \
    lsb-release gnupg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Use an official Python image for the runtime stage
FROM python:3.10-slim

# Copy only necessary files from the builder stage
COPY --from=builder /usr/local /usr/local


# Install dependencies in a single RUN command to reduce layers
RUN apt-get update -y && apt-get install -y \
    wget bzip2 unzip libgl1-mesa-glx libglib2.0-0 git \
    libgoogle-perftools4 libtcmalloc-minimal4 \
    lsb-release gnupg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set environment variables
ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    TZ=Asia/Karachi \
    APP_HOME=/app \
    HOME=/home/myuser \
    PYTHONUNBUFFERED=True \
    GOOGLE_APPLICATION_CREDENTIALS=/etc/gcsfuse_key.json

# Create non-root user
RUN useradd -m myuser \
    && mkdir -p $APP_HOME \
    && chown myuser:myuser $APP_HOME

# Set working directory
WORKDIR $APP_HOME
USER myuser

# Copy local code to the container image with appropriate permissions
COPY --chown=myuser:myuser . $APP_HOME

# Change the permissions of certain files to read-only
RUN chmod 444 stable-diffusion-webui/config.json \
    && chmod 444 stable-diffusion-webui/ui-config.json

# Install Python dependencies
# Use `--no-cache-dir` to reduce image size
RUN python3 -m pip install --no-cache-dir --upgrade pip setuptools

# Start command (includes mounting the GCS bucket)
CMD ["bash", "webui.sh"]
```

## Step 4: Build and Push Docker Image
Build your Docker image using the Dockerfile and push it to a container registry.

## Step 5: Create Kubernetes Deployment Configuration
Utilize the provided `gpu_deployment.yaml` file to set up your Kubernetes deployment.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pictro-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pictro-app
  template:
    metadata:
      labels:
        app: pictro-app
    spec:
      containers:
      - name: pictro-container
        image: Your Docker image URI #GCP ARTIFACT REGISITRY
        resources:
          limits:
            nvidia.com/gpu: 1
          requests:
            cpu: "16"
            memory: "4Gi"
apiVersion: autoscaling/v2beta2
kind: HorizontalPodAutoscaler
metadata:
  name: my-pictro-app-scaler
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: pictro-app  # This should match the name of your Deployment
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 80

```

## Step 6: Deploy the Application
Deploy your application to the Kubernetes cluster using:
```bash
kubectl apply -f gpu_deployment.yaml
kubectl get pods
```

## Step 7: Expose the Application
Create a `service.yaml` file to expose your application on a specific port.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-gpu-service
spec:
  selector:
    app: my-gpu-app # This should match a label in your Pod's metadata
  type: LoadBalancer
  ports:
  - name: http
    protocol: TCP
    port: 80 # The port that the service will serve on
    targetPort: 5000 # The target port on the container

```

Run the following command to apply the service configuration and expose your app:
```bash
kubectl apply -f service.yaml
```

To get the public IP address of your service:
```bash
kubectl get service my-gpu-service
```

## Additional Information
- The `webui.sh` script contains functions for cloning repositories and downloading models only if they don't already exist.
- Make sure to replace placeholders like `Your Image here` with actual values.

## Conclusion
Following these steps will set up your GPU-based container app on GKE Autopilot, allowing for efficient deployment and scaling.

---

Remember to replace placeholders and include any additional information or steps that might be relevant to your specific application or environment.
