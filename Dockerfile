# Define base images
ARG build_image="ubuntu:20.04"
ARG app_image="ubuntu:20.04"

# Build image
FROM --platform=$BUILDPLATFORM ${build_image} AS build
RUN apt-get update && apt-get install -y build-essential git software-properties-common curl

# Add deadsnakes PPA and install Python 3.9
RUN add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y python3.9 python3.9-dev python3.9-distutils python3-pip libsm6 libxext6 libxrender-dev tesseract-ocr

# App image
FROM --platform=$TARGETPLATFORM ${app_image}

# Set DEBIAN_FRONTEND to noninteractive to avoid timezone prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Kolkata

# Update and set up apt sources
RUN sed -i 's/http:\/\/archive.ubuntu.com/http:\/\/mirror.math.princeton.edu\/pub\/ubuntu/g' /etc/apt/sources.list && \
    apt-get update --fix-missing && \
    apt-get install -y tzdata curl software-properties-common && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install Python 3.9 and other dependencies
RUN apt-get install -y python3.9 python3.9-dev python3.9-distutils python3-pip python3-setuptools libsm6 libxext6 libxrender-dev git wget unzip build-essential libjpeg-dev zlib1g-dev libglib2.0-0 libfreetype6-dev liblcms2-dev libopenjp2-7-dev libtiff-dev libwebp-dev libgl1-mesa-glx libxcb1-dev libffi-dev libssl-dev gcc g++

RUN python3.9 -m pip install inference-sdk
# Upgrade pip, setuptools, and wheel
RUN python3.9 -m pip install --upgrade pip setuptools wheel

# Install gevent (binary wheels)
RUN python3.9 -m pip install --only-binary :all: gevent

# Set working directory
WORKDIR /app

# Copy application files
COPY app/requirement.txt . 
COPY app/mainApp.py . 
COPY app/swag.yaml . 
RUN python3.9 -m pip install -r requirement.txt

# Install font for visualization
RUN wget http://sourceforge.net/projects/dejavu/files/dejavu/2.37/dejavu-sans-ttf-2.37.zip && \
    unzip -j dejavu-sans-ttf-2.37.zip dejavu*/ttf/DejaVuSans.ttf && \
    rm dejavu-sans-ttf-2.37.zip

# Default command
CMD ["python3.9", "mainApp.py"]
