
#!/bin/bash

set -Eeuo pipefail

# =========================================
# 0. VALIDAÇÃO INICIAL
# =========================================

if [ "$EUID" -ne 0 ]; then
    echo "ERRO: Execute este script como root."
    exit 1
fi

echo "========================================="
echo " G6 - DEPLOY APPLICATION"
echo "========================================="

# =========================================
# 1. VARIÁVEIS
# =========================================

CURRENT_USER="ubuntu"
USER_HOME="/home/ubuntu"

APP_PATH="${USER_HOME}/app"
VENV_NAME="amb"
VENV_PATH="${USER_HOME}/${VENV_NAME}"

PYSPARK_VERSION="4.2.0"
AWS_REGION="us-east-1"

SERVICE_NAME="jupyterlab"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

JUPYTER_CONFIG_DIR="${USER_HOME}/.jupyter"
JUPYTER_CONFIG="${JUPYTER_CONFIG_DIR}/jupyter_lab_config.py"

APP_STARTUP_SCRIPT="${APP_PATH}/startup/00-spark-config.py"

IPYTHON_STARTUP="${USER_HOME}/.ipython/profile_default/startup"

# AWS Glue
GLUE_JARS_DIR="/opt/aws-glue-catalog/jars"
GLUE_CATALOG_JARS=""

# Logs e resultados
LOG_PATH="${USER_HOME}/logs"
OUTPUT_PATH="${APP_PATH}/output/notebooks"

# Systemd Exporter
SYSTEMD_EXPORTER_VERSION="0.7.0"
SYSTEMD_EXPORTER_PORT="9558"

SYSTEMD_EXPORTER_PATH="/opt/systemd_exporter"
SYSTEMD_EXPORTER_BINARY="${SYSTEMD_EXPORTER_PATH}/systemd_exporter"

SYSTEMD_EXPORTER_SERVICE="/etc/systemd/system/systemd-exporter.service"

# =========================================
# 2. VALIDAÇÃO DE DEPENDÊNCIAS
# =========================================

echo "[1/8] Validando dependências..."

for COMMAND in python3 java curl wget tar systemctl; do
    if ! command -v "$COMMAND" >/dev/null 2>&1; then
        echo "ERRO: Comando não encontrado: $COMMAND"
        exit 1
    fi
done

if ! id "$CURRENT_USER" >/dev/null 2>&1; then
    echo "ERRO: Usuário ${CURRENT_USER} não encontrado."
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo "ERRO: Aplicação não encontrada:"
    echo "$APP_PATH"
    echo "Transfira a aplicação antes de executar o deploy."
    exit 1
fi

if [ ! -f "$APP_STARTUP_SCRIPT" ]; then
    echo "ERRO: Configuração Spark não encontrada:"
    echo "$APP_STARTUP_SCRIPT"
    exit 1
fi

if [ ! -f "${APP_PATH}/scripts/run_pipeline.sh" ]; then
    echo "ERRO: run_pipeline.sh não encontrado."
    exit 1
fi

# =========================================
# 3. VALIDAÇÃO JAVA
# =========================================

echo "[2/8] Validando Java..."

JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")

export JAVA_HOME

echo "JAVA_HOME: ${JAVA_HOME}"

java -version

# =========================================
# 4. VALIDAÇÃO AWS GLUE CLIENT
# =========================================

echo "[3/8] Validando AWS Glue Catalog Client..."

if [ ! -d "$GLUE_JARS_DIR" ]; then
    echo "ERRO: Diretório dos JARs do Glue não encontrado."
    echo "$GLUE_JARS_DIR"
    exit 1
fi

GLUE_CATALOG_JARS=$(
    find "$GLUE_JARS_DIR" \
        -maxdepth 1 \
        -type f \
        -name "*.jar" \
        | sort \
        | paste -sd, -
)

if [ -z "$GLUE_CATALOG_JARS" ]; then
    echo "ERRO: Nenhum JAR encontrado no diretório Glue."
    exit 1
fi

echo "JARs encontrados:"

find "$GLUE_JARS_DIR" \
    -maxdepth 1 \
    -type f \
    -name "*.jar" \
    -printf '%f\n'

# =========================================
# 5. PREPARAÇÃO DOS DIRETÓRIOS
# =========================================

echo "[4/8] Preparando diretórios..."

mkdir -p "$LOG_PATH"
mkdir -p "$OUTPUT_PATH"
mkdir -p "$JUPYTER_CONFIG_DIR"
mkdir -p "$IPYTHON_STARTUP"

chown -R "${CURRENT_USER}:${CURRENT_USER}" \
    "$LOG_PATH" \
    "$OUTPUT_PATH" \
    "$JUPYTER_CONFIG_DIR" \
    "${USER_HOME}/.ipython"

chown -R "${CURRENT_USER}:${CURRENT_USER}" "$APP_PATH"

# =========================================
# 6. AMBIENTE VIRTUAL
# =========================================

echo "[5/8] Configurando ambiente Python..."

if [ ! -d "$VENV_PATH" ]; then
    sudo -u "$CURRENT_USER" python3 -m venv "$VENV_PATH"
fi

if [ ! -x "${VENV_PATH}/bin/python" ]; then
    echo "ERRO: Ambiente virtual inválido."
    exit 1
fi

sudo -u "$CURRENT_USER" \
    "$VENV_PATH/bin/python" -m pip install --upgrade pip

# Instalação das dependências
sudo -u "$CURRENT_USER" \
    "$VENV_PATH/bin/python" -m pip install \
        jupyterlab \
        "pyspark==${PYSPARK_VERSION}" \
        findspark \
        boto3 \
        pandas \
        papermill \
        ipykernel

# Registro do kernel
sudo -u "$CURRENT_USER" \
    "$VENV_PATH/bin/python" -m ipykernel install \
        --user \
        --name amb \
        --display-name "Python (G6)"

# Validação das dependências
sudo -u "$CURRENT_USER" \
    "$VENV_PATH/bin/python" -c "
import pyspark
import boto3
import pandas
import papermill
import ipykernel

print('PySpark:', pyspark.__version__)
print('Boto3:', boto3.__version__)
print('Pandas:', pandas.__version__)
print('Dependências instaladas.')
"

if [ ! -x "${VENV_PATH}/bin/jupyter" ]; then
    echo "ERRO: JupyterLab não foi instalado."
    exit 1
fi

# =========================================
# 7. CONFIGURAÇÃO JUPYTER
# =========================================

echo "[6/8] Configurando JupyterLab..."

if [ -z "${JUPYTER_PASSWORD:-}" ]; then
    echo "ERRO: A variável JUPYTER_PASSWORD não foi definida."
    echo "Forneça a senha por um mecanismo seguro de secrets."
    exit 1
fi

HASH_PASSWD=$(
    sudo -u "$CURRENT_USER" \
        env JUPYTER_PASSWORD="$JUPYTER_PASSWORD" \
        "$VENV_PATH/bin/python" -c '
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

chown "${CURRENT_USER}:${CURRENT_USER}" "$JUPYTER_CONFIG"

chmod 600 "$JUPYTER_CONFIG"

echo "Configuração Jupyter criada."

# =========================================
# 8. CONFIGURAÇÃO IPYTHON STARTUP
# =========================================

echo "Configurando IPython Startup..."

ln -sfn \
    "$APP_STARTUP_SCRIPT" \
    "${IPYTHON_STARTUP}/00-spark-config.py"

chown -R "${CURRENT_USER}:${CURRENT_USER}" \
    "${USER_HOME}/.ipython"

echo "IPython Startup configurado."

# =========================================
# 9. SERVIÇO SYSTEMD JUPYTER
# =========================================

echo "Configurando serviço systemd..."

cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=JupyterLab - G6 Data Processing
Wants=network-online.target
After=network-online.target

[Service]
Type=simple

User=${CURRENT_USER}
Group=${CURRENT_USER}

WorkingDirectory=${USER_HOME}

ExecStart=${VENV_PATH}/bin/jupyter lab --config=${JUPYTER_CONFIG}

Restart=always
RestartSec=10

Environment="JAVA_HOME=${JAVA_HOME}"
Environment="AWS_REGION=${AWS_REGION}"
Environment="AWS_DEFAULT_REGION=${AWS_REGION}"
Environment="GLUE_CATALOG_JARS=${GLUE_CATALOG_JARS}"
Environment="PATH=${VENV_PATH}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

systemctl enable "$SERVICE_NAME"

systemctl restart "$SERVICE_NAME"

sleep 5

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "JupyterLab iniciado com sucesso."
else
    echo "ERRO: JupyterLab não iniciou."

    systemctl status "$SERVICE_NAME" --no-pager

    journalctl -u "$SERVICE_NAME" -n 50 --no-pager

    exit 1
fi

# =========================================
# 10. SYSTEMD EXPORTER
# =========================================

echo "[7/8] Instalando systemd_exporter..."

case "$(uname -m)" in
    x86_64)
        EXPORTER_ARCH="amd64"
        ;;
    aarch64)
        EXPORTER_ARCH="arm64"
        ;;
    *)
        echo "ERRO: Arquitetura não suportada: $(uname -m)"
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

# Limpeza
rm -rf \
    "$EXPORTER_ARCHIVE" \
    "systemd_exporter-${SYSTEMD_EXPORTER_VERSION}.linux-${EXPORTER_ARCH}"

# =========================================
# 11. SERVIÇO SYSTEMD EXPORTER
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

if systemctl is-active --quiet systemd-exporter; then
    echo "systemd_exporter iniciado com sucesso."
else
    echo "ERRO: systemd_exporter não iniciou."

    systemctl status systemd-exporter --no-pager

    exit 1
fi

# =========================================
# 12. PERMISSÕES PIPELINE
# =========================================

echo "Configurando permissões do pipeline..."

chown "${CURRENT_USER}:${CURRENT_USER}" \
    "${APP_PATH}/scripts/run_pipeline.sh"

chmod 750 "${APP_PATH}/scripts/run_pipeline.sh"

chown -R "${CURRENT_USER}:${CURRENT_USER}" \
    "$LOG_PATH" \
    "$OUTPUT_PATH"

# =========================================
# 13. CONFIGURAÇÃO CRON
# =========================================

echo "Configurando execução automática..."

cat > /etc/cron.d/g6-pipeline <<'EOF'
SHELL=/bin/bash
PATH=/home/ubuntu/amb/bin:/usr/local/bin:/usr/bin:/bin

0 2 * * * ubuntu /home/ubuntu/app/scripts/run_pipeline.sh >> /home/ubuntu/logs/pipeline.log 2>&1
EOF

chmod 644 /etc/cron.d/g6-pipeline

systemctl enable cron
systemctl restart cron

if ! systemctl is-active --quiet cron; then
    echo "ERRO: Serviço cron não está ativo."
    exit 1
fi

# =========================================
# 14. TESTES FINAIS
# =========================================

echo "[8/8] Executando testes finais..."

echo
echo "========================================="
echo " JUPYTERLAB"
echo "========================================="

systemctl is-active "$SERVICE_NAME"

ss -lntp | grep ':8080' || true

echo
echo "========================================="
echo " SPARK / GLUE"
echo "========================================="

echo "Java:"
java -version

echo "AWS Region: ${AWS_REGION}"

echo "Glue JARs:"

find "$GLUE_JARS_DIR" \
    -maxdepth 1 \
    -type f \
    -name "*.jar" \
    -printf '%f\n'

echo
echo "========================================="
echo " SYSTEMD EXPORTER"
echo "========================================="

systemctl is-active systemd-exporter

ss -lntp | grep ":${SYSTEMD_EXPORTER_PORT}" || true

curl -fsS \
    "http://localhost:${SYSTEMD_EXPORTER_PORT}/metrics" \
    | grep 'systemd_unit_state.*jupyterlab.service' \
    || echo "Métrica do Jupyter ainda não encontrada."

echo
echo "========================================="
echo " CRON"
echo "========================================="

systemctl is-active cron

cat /etc/cron.d/g6-pipeline

echo
echo "========================================="
echo " DEPLOY CONCLUÍDO"
echo "========================================="

echo "Usuário: ${CURRENT_USER}"
echo "Aplicação: ${APP_PATH}"
echo "Virtualenv: ${VENV_PATH}"
echo "PySpark: ${PYSPARK_VERSION}"
echo "Java Home: ${JAVA_HOME}"
echo "AWS Region: ${AWS_REGION}"
echo "Glue JARs: ${GLUE_JARS_DIR}"
echo "Jupyter HTTP: 8080"
echo "Systemd Exporter: ${SYSTEMD_EXPORTER_PORT}"
echo "Pipeline: Diário às 02:00"

echo "========================================="