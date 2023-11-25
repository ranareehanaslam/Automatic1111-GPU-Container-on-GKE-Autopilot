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
