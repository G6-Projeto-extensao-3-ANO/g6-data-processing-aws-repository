#!/bin/bash

set -e

echo "Preparando Ambiente (Aguarde...)"
apt-get update -y
apt-get upgrade -y

apt-get install -y \
    curl \
    wget \
    git \
    unzip \
    jq \
    ca-certificates \
    gnupg \
    lsb-release \
    python3 \
    python3-pip \
    python3-venv \
    tar

systemctl enable amazon-ssm-agent || true
systemctl start amazon-ssm-agent || true

install -m 0755 -d /etc/apt/keyrings

echo "Baixando Docker (Aguarde...)"

apt install docker.io -y

systemctl enable docker
systemctl start docker

usermod -aG docker ubuntu