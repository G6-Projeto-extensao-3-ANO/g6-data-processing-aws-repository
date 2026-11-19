
#!/bin/bash

set -Eeuo pipefail

# =========================================
# 1. CONFIGURAÇÕES
# =========================================

CURRENT_USER="ubuntu"
USER_HOME="/home/ubuntu"
APP_PATH="${USER_HOME}/app"
JUPYTER_CONFIG_DIR="${USER_HOME}/.jupyter"
JUPYTER_CONFIG="${JUPYTER_CONFIG_DIR}/jupyter_lab_config.py"
IPYTHON_STARTUP="${USER_HOME}/.ipython/profile_default/startup"
LOG_PATH="${USER_HOME}/logs"
SERVICE_NAME="jupyterlab"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
DOCKER_IMAGE="g6-glue-runtime:6.0"
CONTAINER_NAME="g6-glue-runtime"
AWS_REGION="us-east-1"
JUPYTER_PASSWORD="TESTES"

# Systemd Exporter
SYSTEMD_EXPORTER_VERSION="0.7.0"
SYSTEMD_EXPORTER_PORT="9558"
SYSTEMD_EXPORTER_PATH="/opt/systemd_exporter"
SYSTEMD_EXPORTER_BINARY="${SYSTEMD_EXPORTER_PATH}/systemd_exporter"
SYSTEMD_EXPORTER_SERVICE="/etc/systemd/system/systemd-exporter.service"

# =========================================
# 2. VALIDAÇÃO INICIAL
# =========================================

if [ "$EUID" -ne 0 ]; then
    echo "ERRO: Execute como root."
    exit 1
fi

echo "========================================="
echo " G6 - DEPLOY APPLICATION"
echo "========================================="

# =========================================
# 3. DEPENDÊNCIAS
# =========================================

for COMMAND in docker curl wget systemctl; do

    if ! command -v "$COMMAND" >/dev/null 2>&1; then

        echo "ERRO: Comando não encontrado: $COMMAND"

        exit 1

    fi

done

if ! id "$CURRENT_USER" >/dev/null 2>&1; then

    echo "ERRO: Usuário ubuntu não encontrado."

    exit 1

fi

if [ ! -d "$APP_PATH" ]; then

    echo "ERRO: Aplicação não encontrada: $APP_PATH"

    exit 1

fi

if [ ! -f "${APP_PATH}/startup/00-spark-config.py" ]; then

    echo "ERRO: Startup Spark não encontrado."

    exit 1

fi

if [ ! -f "${APP_PATH}/config/config.py" ]; then

    echo "ERRO: config.py não encontrado."

    exit 1

fi

# =========================================
# 4. VALIDAR IMAGEM GLUE
# =========================================

echo "[1/8] Validando imagem AWS Glue..."

if ! docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then

    echo "ERRO: Imagem Docker não encontrada."

    echo "Execute install.sh novamente."

    exit 1

fi

# =========================================
# 5. PREPARAR DIRETÓRIOS
# =========================================

echo "[2/8] Preparando diretórios..."

mkdir -p \
    "$LOG_PATH" \
    "$JUPYTER_CONFIG_DIR" \
    "$IPYTHON_STARTUP"

chown -R ubuntu:ubuntu \
    "$LOG_PATH" \
    "$JUPYTER_CONFIG_DIR" \
    "${USER_HOME}/.ipython"

chown -R ubuntu:ubuntu "$APP_PATH"

# =========================================
# 6. CONFIGURAÇÃO JUPYTER
# =========================================

echo "[3/8] Configurando JupyterLab..."

if [ -z "${JUPYTER_PASSWORD:-}" ]; then

    echo "ERRO: JUPYTER_PASSWORD não definida."

    exit 1

fi

HASH_PASSWD=$(
    docker run --rm \
        --entrypoint python3 \
        -e JUPYTER_PASSWORD="$JUPYTER_PASSWORD" \
        "$DOCKER_IMAGE" \
        -c '
import os
from jupyter_server.auth import passwd

print(passwd(os.environ["JUPYTER_PASSWORD"]))
'
)

unset JUPYTER_PASSWORD

cat > "$JUPYTER_CONFIG" <<EOF

c.ServerApp.ip = '0.0.0.0'

c.ServerApp.port = 8080

c.ServerApp.open_browser = False

c.ServerApp.allow_remote_access = True

c.ServerApp.identity_provider_class = 'jupyter_server.auth.identity.PasswordIdentityProvider'

c.PasswordIdentityProvider.hashed_password = '${HASH_PASSWD}'

EOF

chown ubuntu:ubuntu "$JUPYTER_CONFIG"

chmod 600 "$JUPYTER_CONFIG"

# =========================================
# 7. IPYTHON STARTUP
# =========================================

echo "[4/8] Configurando IPython..."

ln -sfn \
    "/home/hadoop/app/startup/00-spark-config.py" \
    "${IPYTHON_STARTUP}/00-spark-config.py"

chown -h ubuntu:ubuntu \
    "${IPYTHON_STARTUP}/00-spark-config.py"

# =========================================
# 8. SERVIÇO JUPYTER DOCKER
# =========================================

echo "[5/8] Configurando container JupyterLab..."

cat > "$SERVICE_PATH" <<EOF

[Unit]
Description=G6 JupyterLab AWS Glue 6.0

Requires=docker.service

After=docker.service network-online.target

[Service]
Type=simple

User=root

WorkingDirectory=/home/ubuntu

ExecStartPre=-/usr/bin/docker rm -f ${CONTAINER_NAME}

ExecStart=/usr/bin/docker run --rm \
    --name g6-glue-runtime \
    --network host \
    --restart=no \
    --entrypoint jupyter \
    -e AWS_REGION=us-east-1 \
    -e AWS_DEFAULT_REGION=us-east-1 \
    -e HOME=/home/hadoop \
    -e PYTHONPATH=/home/hadoop/app \
    -e IPYTHONDIR=/home/hadoop/.ipython \
    -v /home/ubuntu/app:/home/hadoop/app \
    -v /home/ubuntu/logs:/home/hadoop/logs \
    -v /home/ubuntu/.jupyter:/home/hadoop/.jupyter \
    -v /home/ubuntu/.ipython:/home/hadoop/.ipython \
    g6-glue-runtime:6.0 \
    lab \
    --ip=0.0.0.0 \
    --port=8080 \
    --no-browser \
    --ServerApp.allow_remote_access=True

ExecStop=/usr/bin/docker stop ${CONTAINER_NAME}

Restart=always

RestartSec=10

[Install]
WantedBy=multi-user.target

EOF

systemctl daemon-reload

systemctl enable "$SERVICE_NAME"

systemctl restart "$SERVICE_NAME"

sleep 10

if ! systemctl is-active --quiet "$SERVICE_NAME"; then

    echo "ERRO: JupyterLab não iniciou."

    journalctl -u "$SERVICE_NAME" -n 80 --no-pager

    exit 1

fi

# =========================================
# 9. SYSTEMD EXPORTER
# =========================================

echo "[6/8] Instalando systemd_exporter..."

case "$(uname -m)" in

    x86_64)
        EXPORTER_ARCH="amd64"
        ;;

    aarch64)
        EXPORTER_ARCH="arm64"
        ;;

    *)
        echo "Arquitetura não suportada."

        exit 1
        ;;

esac

EXPORTER_ARCHIVE="systemd_exporter-${SYSTEMD_EXPORTER_VERSION}.linux-${EXPORTER_ARCH}.tar.gz"

EXPORTER_URL="https://github.com/prometheus-community/systemd_exporter/releases/download/v${SYSTEMD_EXPORTER_VERSION}/${EXPORTER_ARCHIVE}"

mkdir -p "$SYSTEMD_EXPORTER_PATH"

cd /tmp

curl -fL "$EXPORTER_URL" -o "$EXPORTER_ARCHIVE"

tar -xzf "$EXPORTER_ARCHIVE"

cp \
    "systemd_exporter-${SYSTEMD_EXPORTER_VERSION}.linux-${EXPORTER_ARCH}/systemd_exporter" \
    "$SYSTEMD_EXPORTER_BINARY"

chmod 755 "$SYSTEMD_EXPORTER_BINARY"

rm -rf \
    "$EXPORTER_ARCHIVE" \
    "systemd_exporter-${SYSTEMD_EXPORTER_VERSION}.linux-${EXPORTER_ARCH}"

# =========================================
# 10. SYSTEMD EXPORTER SERVICE
# =========================================

cat > "$SYSTEMD_EXPORTER_SERVICE" <<EOF

[Unit]
Description=Prometheus systemd Exporter
After=network.target

[Service]
Type=simple

ExecStart=${SYSTEMD_EXPORTER_BINARY} --web.listen-address=0.0.0.0:${SYSTEMD_EXPORTER_PORT}

Restart=always

RestartSec=5

[Install]
WantedBy=multi-user.target

EOF

systemctl daemon-reload

systemctl enable systemd-exporter

systemctl restart systemd-exporter

sleep 3

# =========================================
# 11. CRON
# =========================================

echo "[7/8] Configurando cron..."

cat > /etc/cron.d/g6-pipeline <<'EOF'
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin

0 2 * * * ubuntu /home/ubuntu/app/scripts/run_pipeline.sh >> /home/ubuntu/logs/pipeline.log 2>&1
EOF

chmod 644 /etc/cron.d/g6-pipeline

systemctl enable cron

systemctl restart cron

# =========================================
# 12. TESTES FINAIS
# =========================================

echo "[8/8] Testes finais..."

docker exec "$CONTAINER_NAME" python3 -c "
import pyspark
import boto3
import awsglue

print('Spark:', pyspark.__version__)
print('Boto3:', boto3.__version__)
print('Glue Libraries: OK')
"

systemctl is-active "$SERVICE_NAME"

systemctl is-active systemd-exporter

systemctl is-active cron

curl -fsS \
    "http://localhost:${SYSTEMD_EXPORTER_PORT}/metrics" \
    >/dev/null

echo "========================================="
echo " DEPLOY CONCLUÍDO"
echo "========================================="

echo "Runtime: AWS Glue 6.0"

echo "Spark: 4.1.1"

echo "Python: 3.13"

echo "JupyterLab: 8080"

echo "Systemd Exporter: ${SYSTEMD_EXPORTER_PORT}"

echo "Pipeline: Diário às 02:00"

echo "========================================="