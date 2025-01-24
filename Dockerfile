# Define base images
ARG build_image="ubuntu:20.04"
ARG app_image="ubuntu:20.04"

# Build image
FROM --platform=$BUILDPLATFORM ${build_image} AS build
RUN apt-get update
RUN apt-get install -y build-essential git software-properties-common

# Add deadsnakes PPA and install Python 3.8
RUN add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y python3.8 python3.8-dev python3.8-distutils python3-pip python3-setuptools libsm6 libxext6 libxrender-dev tesseract-ocr

# Ensure pip is installed for Python 3.7
RUN curl https://bootstrap.pypa.io/pip/3.7/get-pip.py -o get-pip.py && python3.7 get-pip.py


# Should CUDA be enabled?
ARG cuda=0
# Compile with support for Tensor Cores?
ARG cuda_tc=0

# Get and compile darknet
WORKDIR /src
RUN git clone -n https://github.com/AlexeyAB/darknet.git
WORKDIR /src/darknet
RUN git checkout 38a164bcb9e017f8c9c3645a39419320e217545e
RUN sed -i -e "s!OPENMP=0!OPENMP=1!g" Makefile && \
    sed -i -e "s!AVX=0!AVX=1!g" Makefile && \
    sed -i -e "s!LIBSO=0!LIBSO=1!g" Makefile && \
    sed -i -e "s!GPU=0!GPU=${cuda}!g" Makefile && \
    sed -i -e "s!CUDNN=0!CUDNN=${cuda}!g" Makefile && \
    sed -i -e "s!CUDNN_HALF=0!CUDNN_HALF=${cuda_tc}!g" Makefile && \
    make

# App image:
FROM --platform=$TARGETPLATFORM ${app_image}

# Clean apt cache and ensure a writable filesystem
RUN apt-get clean
RUN rm -rf /var/lib/apt/lists/*
RUN apt-get update

# Change mirror to avoid repository issues
RUN sed -i 's/http:\/\/archive.ubuntu.com/http:\/\/mirror.math.princeton.edu\/pub\/ubuntu/g' /etc/apt/sources.list
RUN apt-get update

# Install required packages
RUN apt-get install -y python3.8 
RUN apt-get install -y python3.8-dev 
RUN apt-get install -y python3.8-distutils 
RUN apt-get install -y python3-pip 
RUN apt-get install -y python3-setuptools 
RUN apt-get install -y libsm6 
RUN apt-get install -y libxext6 
RUN apt-get install -y libxrender-dev 
RUN apt-get install -y git

# Install system dependencies for Pillow
RUN apt-get update --fix-missing && apt-get install -y \
    build-essential \
    libjpeg-dev \
    zlib1g-dev \
    libfreetype6-dev \
    liblcms2-dev \
    libopenjp2-7-dev \
    libtiff-dev \
    libwebp-dev \
    libgl1-mesa-glx \
    libxcb1-dev \
    && rm -rf /var/lib/apt/lists/*

# Upgrade setuptools
RUN python3.8 -m pip install --upgrade setuptools

# Install Pillow via pip
RUN python3.8 -m pip install --upgrade pip
RUN python3.8 -m pip install Pillow

# Install YOLOv8 from GitHub
RUN python3.8 -m pip install git+https://github.com/ultralytics/ultralytics.git

# Set your working directory
WORKDIR /app

# Copy requirements.txt and install dependencies
COPY app/requirement.txt . 
COPY app/mainApp.py .
COPY app/swag.yaml .
RUN python3.7 -m pip install --no-cache-dir -r requirement.txt

# Get darknet from build image
COPY --from=build /src/darknet/libdarknet.so .
COPY --from=build /src/darknet/build/darknet/x64/darknet.py .
COPY --from=build /src/darknet/cfg data/
COPY --from=build /src/darknet/data data/

# Get release version of yolov4.cfg
WORKDIR /app/data
RUN mv yolov4.cfg yolov4.cfg.github
RUN wget --no-check-certificate 'https://drive.google.com/uc?export=download&id=15NIlaC-iPr5TegGDhzevyUmLQuQG7cyj' -O yolov4.weights

COPY yolov4.cfg .
# Reconfigure to avoid out-of-memory errors
RUN sed -i -e "s!subdivisions=8!subdivisions=64!g" yolov4.cfg
COPY obj.data .
COPY obj.names .

# Install font
RUN wget http://sourceforge.net/projects/dejavu/files/dejavu/2.37/dejavu-sans-ttf-2.37.zip
RUN unzip -j dejavu-sans-ttf-2.37.zip dejavu*/ttf/DejaVuSans.ttf
RUN rm dejavu-sans-ttf-2.37.zip

WORKDIR /app
CMD ["python3.8", "mainApp.py"]