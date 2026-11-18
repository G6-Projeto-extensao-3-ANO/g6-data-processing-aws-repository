
#!/bin/bash

set -Eeuo pipefail

echo "========================================="
echo " G6 - INSTALL ENVIRONMENT"
echo "========================================="

# =========================================
# 1. DEPENDÊNCIAS DO HOST
# =========================================

apt-get update -y

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
    docker.io

# =========================================
# 2. SERVIÇOS
# =========================================

systemctl enable amazon-ssm-agent || true
systemctl start amazon-ssm-agent || true

systemctl enable docker
systemctl start docker

systemctl enable cron
systemctl start cron

# =========================================
# 3. USUÁRIO
# =========================================

usermod -aG docker ubuntu

# =========================================
# 4. DIRETÓRIOS
# =========================================

mkdir -p /opt/g6-glue

mkdir -p /home/ubuntu/logs

mkdir -p /home/ubuntu/.jupyter

mkdir -p /home/ubuntu/.ipython/profile_default/startup

chown -R ubuntu:ubuntu \
    /home/ubuntu/logs \
    /home/ubuntu/.jupyter \
    /home/ubuntu/.ipython

# =========================================
# 5. DOCKERFILE GLUE 6.0
# =========================================

cat > /opt/g6-glue/Dockerfile <<'EOF'

FROM public.ecr.aws/glue/aws-glue-libs:6.0

USER root

RUN python3 -m pip install \
    --no-cache-dir \
    --root-user-action=ignore \
    jupyterlab \
    papermill \
    boto3 \
    pandas \
    ipykernel \
    findspark

RUN python3 -m ipykernel install \
    --sys-prefix \
    --name glue6 \
    --display-name "Python (AWS Glue 6.0)"

RUN mkdir -p \
    /home/hadoop/app \
    /home/hadoop/.jupyter \
    /home/hadoop/.ipython/profile_default/startup \
    /home/hadoop/logs

ENV HOME=/home/hadoop

ENV PYTHONUNBUFFERED=1

ENV AWS_DEFAULT_REGION=us-east-1

WORKDIR /home/hadoop

USER hadoop

EXPOSE 8080

CMD ["jupyter", "lab", \
     "--ip=0.0.0.0", \
     "--port=8080", \
     "--no-browser", \
     "--ServerApp.allow_remote_access=True"]

EOF

# =========================================
# 6. BUILD DA IMAGEM
# =========================================

docker build \
    -t g6-glue-runtime:6.0 \
    /opt/g6-glue

# =========================================
# 7. VALIDAÇÕES
# =========================================

docker run --rm \
    g6-glue-runtime:6.0 \
    python3 -c "
import pyspark
import awsglue
import boto3

print('PySpark:', pyspark.__version__)
print('Boto3:', boto3.__version__)
print('AWS Glue Libraries: OK')
"

docker run --rm \
    g6-glue-runtime:6.0 \
    java -version

echo "========================================="
echo " INSTALAÇÃO CONCLUÍDA"
echo "========================================="
