```bash
#!/bin/bash

set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "========================================="
echo " G6 - INSTALL ENVIRONMENT"
echo "========================================="

# =========================================
# 1. DEPENDÊNCIAS DO HOST
# =========================================

PACKAGES=(
    curl
    wget
    git
    unzip
    jq
    ca-certificates
    python3
    python3-pip
    python3-venv
    tar
    gzip
    util-linux
    cron
    docker.io
)

MISSING_PACKAGES=()

for PACKAGE in "${PACKAGES[@]}"; do

    if ! dpkg -s "$PACKAGE" >/dev/null 2>&1; then
        MISSING_PACKAGES+=("$PACKAGE")
    fi

done

if [ "${#MISSING_PACKAGES[@]}" -gt 0 ]; then

    echo "Instalando dependências ausentes..."

    apt-get install -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        "${MISSING_PACKAGES[@]}"

else

    echo "Dependências do host já instaladas."

fi

# =========================================
# 2. SERVIÇOS
# =========================================

echo "Configurando serviços..."

systemctl enable amazon-ssm-agent >/dev/null 2>&1 || true
systemctl start amazon-ssm-agent >/dev/null 2>&1 || true

systemctl enable docker >/dev/null 2>&1 || true
systemctl start docker

systemctl enable cron >/dev/null 2>&1 || true
systemctl start cron

# =========================================
# 3. USUÁRIO
# =========================================

if ! id -nG ubuntu | grep -qw docker; then

    usermod -aG docker ubuntu

fi

# =========================================
# 4. DIRETÓRIOS
# =========================================

mkdir -p \
    /opt/g6-glue \
    /home/ubuntu/logs \
    /home/ubuntu/.jupyter \
    /home/ubuntu/.ipython/profile_default/startup

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

IMAGE_NAME="g6-glue-runtime:6.0"

echo "Verificando imagem Docker..."

if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then

    echo "Imagem existente encontrada."

else

    echo "Imagem inexistente. Construindo runtime..."

    docker build \
        --pull=false \
        -t "$IMAGE_NAME" \
        /opt/g6-glue

fi

# =========================================
# 7. VALIDAÇÃO
# =========================================

echo "Validando runtime AWS Glue..."

docker run --rm \
    --entrypoint python3 \
    "$IMAGE_NAME" \
    -c "
import pyspark
import awsglue
import boto3
import papermill
import jupyterlab
import ipykernel

print('PySpark:', pyspark.__version__)
print('Boto3:', boto3.__version__)
print('Papermill:', papermill.__version__)
print('JupyterLab:', jupyterlab.__version__)
print('IPython Kernel:', ipykernel.__version__)
print('AWS Glue Libraries: OK')
"

echo "Validando Java..."

docker run --rm \
    --entrypoint java \
    "$IMAGE_NAME" \
    -version

echo "========================================="
echo " INSTALAÇÃO CONCLUÍDA"
echo "========================================="
```