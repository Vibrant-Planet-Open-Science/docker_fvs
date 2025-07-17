FROM ubuntu:latest AS builder

USER root

WORKDIR /build
ENV FC=gfortran
ARG FVS_VERSION=2024.4
RUN apt-get update &&\
 apt-get install -y git build-essential gfortran cmake unixodbc-dev rename
RUN git clone -b "${FVS_VERSION}" --recurse-submodules https://github.com/USDAForestService/ForestVegetationSimulator.git &&\
 cd /build/ForestVegetationSimulator/volume/NVEL &&\
 rename 'y/A-Z/a-z/' *
RUN cd /build/ForestVegetationSimulator/bin &&\
 make US -j5


FROM python:3.11-slim AS runtime
ENV PIP_PREFER_BINARY=1
RUN apt-get update &&\
 apt-get install -y git build-essential gfortran cmake unixodbc-dev &&\
 pip install --upgrade pip pip-tools &&\
 pip install --no-cache-dir --upgrade pytest &&\
 apt-get clean &&\
 rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/ForestVegetationSimulator/bin/FVS??.so /usr/local/lib
COPY --from=builder /build/ForestVegetationSimulator/bin/FVS?? /usr/local/bin