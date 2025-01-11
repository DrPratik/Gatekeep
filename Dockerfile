# Define base images
ARG build_image="ubuntu:18.04"
ARG app_image="ubuntu:18.04"

# Build image
FROM ${build_image} AS build
RUN apt-get update
RUN apt-get install -y build-essential git

# Install required libraries for gevent and pytesseract
RUN apt-get install -y python3.7 python3.7-dev python3-pip python3-setuptools libsm6 libxext6 libxrender-dev tesseract-ocr

# Install Python 3.7 and required packages
RUN apt-get update && \
    apt-get install -y python3.7 python3.7-dev python3-pip python3-setuptools libsm6 libxext6 curl

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
FROM ${app_image}

# Clean apt cache and ensure a writable filesystem
RUN apt-get clean
RUN rm -rf /var/lib/apt/lists/*
RUN apt-get update

# Change mirror to avoid repository issues
RUN sed -i 's/http:\/\/archive.ubuntu.com/http:\/\/mirror.math.princeton.edu\/pub\/ubuntu/g' /etc/apt/sources.list
RUN apt-get update

# Install required packages
RUN apt-get install -y python3.7 python3.7-dev python3-pip python3-setuptools libsm6 libxext6 libxrender-dev tesseract-ocr

RUN python3.7 -m pip install Pillow

# Install pip3 for Python 3.7
#RUN python3.7 -m ensurepip --upgrade
RUN python3.7 -m pip install --upgrade pip

FROM python:3.7

# Install system dependencies for Pillow
RUN apt-get update --fix-missing && apt-get install -y \
    build-essential \
    libjpeg-dev \
    tesseract-ocr \
    zlib1g-dev \
    libgl1-mesa-glx \
    libfreetype6-dev \
    liblcms2-dev \
    libopenjp2-7-dev \  
    libimagequant-dev \
    libxcb1-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Pillow via pip
RUN pip install --upgrade pip
RUN pip install Pillow

# Set your working directory
WORKDIR /app

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
COPY yolov4.cfg .
# Reconfigure to avoid out-of-memory errors
RUN sed -i -e "s!subdivisions=8!subdivisions=64!g" yolov4.cfg
COPY obj.data .
COPY obj.names .
COPY yolov4.weights .

# Install font
RUN wget http://sourceforge.net/projects/dejavu/files/dejavu/2.37/dejavu-sans-ttf-2.37.zip
RUN unzip -j dejavu-sans-ttf-2.37.zip dejavu*/ttf/DejaVuSans.ttf
RUN rm dejavu-sans-ttf-2.37.zip

# Model to use (defaults to yolov3_coco):
ARG weights_file="data/yolov4.weights"
ARG config_file="data/yolov4.cfg"
ARG meta_file="data/obj.data"
ENV weights_file=${weights_file}
ENV config_file=${config_file}
ENV meta_file=${meta_file}


WORKDIR /app
CMD ["python3.7", "mainApp.py"]
