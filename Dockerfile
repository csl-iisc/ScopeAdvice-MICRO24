FROM nvidia/cuda:11.2.2-devel-ubuntu20.04
WORKDIR ./scope-advice-micro24
RUN apt-get update \
  && apt-get install -y build-essential xutils-dev bison zlib1g-dev flex libglu1-mesa-dev vim git bc \
  && apt-get install -y python3
COPY . .
