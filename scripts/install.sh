
#!/bin/bash

set -Eeuo pipefail

echo "Preparando ambiente..."

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
    tar \
    gzip \
    util-linux \
    cron \
    openjdk-21-jre-headless \
    docker.io

systemctl enable amazon-ssm-agent || true
systemctl start amazon-ssm-agent || true

systemctl enable docker
systemctl start docker

usermod -aG docker ubuntu

systemctl enable cron
systemctl start cron

echo "Validando instalações..."

python3 --version
python3 -m pip --version
java -version
docker --version

systemctl is-active docker
systemctl is-active cron

echo "Ambiente preparado com sucesso!"