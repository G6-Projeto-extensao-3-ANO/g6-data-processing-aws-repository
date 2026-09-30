#!/bin/bash

set -e

VENV_NAME="amb"
VENV_PATH="/home/ubuntu/${VENV_NAME}"

SERVICE_NAME="jupyterlab"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

MY_PASSWD="urubu100"

USER_HOME="/home/ubuntu"
CURRENT_USER="ubuntu"

# =========================================
# CONFIGURAÇÕES DO MONITORAMENTO
# =========================================

SYSTEMD_EXPORTER_VERSION="0.7.0"
SYSTEMD_EXPORTER_PORT="9558"

SYSTEMD_EXPORTER_PATH="/opt/systemd_exporter"
SYSTEMD_EXPORTER_BINARY="${SYSTEMD_EXPORTER_PATH}/systemd_exporter"

SYSTEMD_EXPORTER_SERVICE="/etc/systemd/system/systemd-exporter.service"

echo "========================================="
echo " Instalando JupyterLab"
echo "========================================="

echo "[1/9] Atualizando sistema..."

apt update
apt upgrade -y

echo "[2/9] Instalando dependências..."

apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    curl \
    wget \
    tar

echo "[3/9] Criando ambiente virtual..."

if [ -d "$VENV_PATH" ]; then
    echo "Ambiente virtual existente encontrado."
else
    sudo -u "$CURRENT_USER" python3 -m venv "$VENV_PATH"
fi

echo "[4/9] Instalando JupyterLab, PySpark e Findspark..."

sudo -u "$CURRENT_USER" "$VENV_PATH/bin/python" -m pip install --upgrade pip

sudo -u "$CURRENT_USER" "$VENV_PATH/bin/python" -m pip install \
    jupyterlab \
    pyspark \
    findspark

echo "[5/9] Verificando instalação..."

if [ ! -f "$VENV_PATH/bin/jupyter" ]; then
    echo "ERRO: Jupyter não foi instalado corretamente."
    exit 1
fi

"$VENV_PATH/bin/jupyter" --version

echo "[6/9] Configurando JupyterLab..."

mkdir -p "$USER_HOME/.jupyter"

HASH_PASSWD=$(
    sudo -u "$CURRENT_USER" "$VENV_PATH/bin/python" -c \
    "from jupyter_server.auth import passwd; print(passwd('$MY_PASSWD'))"
)

cat > "$USER_HOME/.jupyter/jupyter_lab_config.py" <<EOF
c.ServerApp.ip = '0.0.0.0'
c.ServerApp.port = 8080
c.ServerApp.open_browser = False
c.ServerApp.allow_remote_access = True

c.ServerApp.identity_provider_class = 'jupyter_server.auth.identity.PasswordIdentityProvider'
c.PasswordIdentityProvider.hashed_password = '$HASH_PASSWD'
EOF

chown -R "$CURRENT_USER:$CURRENT_USER" "$USER_HOME/.jupyter"

echo "Configuração criada em:"
echo "$USER_HOME/.jupyter/jupyter_lab_config.py"


# =========================================
# JUPYTER SYSTEMD
# =========================================

echo "[7/9] Criando serviço systemd do Jupyter..."

cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=JupyterLab
After=network.target

[Service]
Type=simple

User=ubuntu
Group=ubuntu

WorkingDirectory=/home/ubuntu

ExecStart=/home/ubuntu/amb/bin/jupyter lab --config=/home/ubuntu/.jupyter/jupyter_lab_config.py

Restart=always
RestartSec=10

Environment="PATH=/home/ubuntu/amb/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
WantedBy=multi-user.target
EOF

echo "Serviço criado em:"
echo "$SERVICE_PATH"

systemctl daemon-reload

systemctl enable "$SERVICE_NAME"

systemctl restart "$SERVICE_NAME"

sleep 5

echo "Verificando JupyterLab..."

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "JupyterLab está funcionando!"
else
    echo "ERRO: JupyterLab não iniciou."

    systemctl status "$SERVICE_NAME" --no-pager

    echo
    echo "Logs:"
    journalctl -u "$SERVICE_NAME" -n 50 --no-pager

    exit 1
fi


# =========================================
# SYSTEMD EXPORTER
# =========================================

echo "[8/9] Instalando systemd_exporter..."

mkdir -p "$SYSTEMD_EXPORTER_PATH"

cd /tmp

wget -q \
    "https://github.com/prometheus-community/systemd_exporter/releases/download/v${SYSTEMD_EXPORTER_VERSION}/systemd_exporter-${SYSTEMD_EXPORTER_VERSION}.linux-amd64.tar.gz" \
    -O systemd_exporter.tar.gz

tar -xzf systemd_exporter.tar.gz

cp \
    "systemd_exporter-${SYSTEMD_EXPORTER_VERSION}.linux-amd64/systemd_exporter" \
    "$SYSTEMD_EXPORTER_BINARY"

chmod +x "$SYSTEMD_EXPORTER_BINARY"

echo "systemd_exporter instalado em:"
echo "$SYSTEMD_EXPORTER_BINARY"


# =========================================
# SERVIÇO SYSTEMD EXPORTER
# =========================================

cat > "$SYSTEMD_EXPORTER_SERVICE" <<EOF
[Unit]
Description=Prometheus systemd Exporter
After=network.target

[Service]
Type=simple

ExecStart=${SYSTEMD_EXPORTER_BINARY} \
    --web.listen-address=0.0.0.0:${SYSTEMD_EXPORTER_PORT}

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

systemctl enable systemd-exporter

systemctl restart systemd-exporter

sleep 3

echo "Verificando systemd_exporter..."

if systemctl is-active --quiet systemd-exporter; then
    echo "systemd_exporter está funcionando!"
else
    echo "ERRO: systemd_exporter não iniciou."

    systemctl status systemd-exporter --no-pager

    exit 1
fi


# =========================================
# TESTES
# =========================================

echo "[9/9] Testando métricas..."

echo
echo "========================================="
echo " JUPYTER"
echo "========================================="

systemctl is-active "$SERVICE_NAME"

echo
echo "Porta 8080:"
ss -lntp | grep ':8080' || true

echo
echo "========================================="
echo " SYSTEMD EXPORTER"
echo "========================================="

echo "Porta:"
ss -lntp | grep ":${SYSTEMD_EXPORTER_PORT}" || true

echo
echo "Métrica do Jupyter:"

curl -s "http://localhost:${SYSTEMD_EXPORTER_PORT}/metrics" \
    | grep 'jupyterlab.service' \
    || echo "Métrica do Jupyter ainda não encontrada."

echo
echo "========================================="
echo " Instalação concluída"
echo "========================================="

echo "VENV:"
echo "$VENV_PATH"

echo
echo "Jupyter:"
echo "$VENV_PATH/bin/jupyter"

echo
echo "Jupyter HTTP:"
echo "8080"

echo
echo "systemd_exporter:"
echo "${SYSTEMD_EXPORTER_PORT}"

echo
echo "Métrica:"
echo "node_systemd_unit_state{name=\"jupyterlab.service\",state=\"active\"}"

echo "========================================="