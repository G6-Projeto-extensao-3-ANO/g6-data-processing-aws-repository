#!/bin/bash

set -e

VENV_NAME="amb"
VENV_PATH="/home/ubuntu/${VENV_NAME}"

SERVICE_NAME="jupyterlab"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

MY_PASSWD="urubu100"

USER_HOME="/home/ubuntu"
CURRENT_USER="ubuntu"

echo "========================================="
echo " Instalando JupyterLab"
echo "========================================="

echo "[1/7] Atualizando sistema..."

apt update
apt upgrade -y

echo "[2/7] Instalando dependências..."

apt install -y \
    python3 \
    python3-pip \
    python3-venv

echo "[3/7] Criando ambiente virtual..."

# Remove eventual ambiente quebrado
if [ -d "$VENV_PATH" ]; then
    echo "Ambiente virtual existente encontrado."
else
    sudo -u "$CURRENT_USER" python3 -m venv "$VENV_PATH"
fi

echo "[4/7] Instalando JupyterLab, PySpark e Findspark..."

sudo -u "$CURRENT_USER" "$VENV_PATH/bin/python" -m pip install --upgrade pip

sudo -u "$CURRENT_USER" "$VENV_PATH/bin/python" -m pip install \
    jupyterlab \
    pyspark \
    findspark

echo "[5/7] Verificando instalação..."

if [ ! -f "$VENV_PATH/bin/jupyter" ]; then
    echo "ERRO: Jupyter não foi instalado corretamente."
    exit 1
fi

"$VENV_PATH/bin/jupyter" --version

echo "[6/7] Configurando JupyterLab..."

mkdir -p "$USER_HOME/.jupyter"

# Gera o hash da senha utilizando o Python do próprio ambiente virtual
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

echo "[7/7] Criando serviço systemd..."

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

echo "Recarregando systemd..."

systemctl daemon-reload

echo "Habilitando JupyterLab..."

systemctl enable "$SERVICE_NAME"

echo "Reiniciando JupyterLab..."

systemctl restart "$SERVICE_NAME"

sleep 5

echo "========================================="
echo " Verificando JupyterLab"
echo "========================================="

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "JupyterLab está funcionando!"
else
    echo "ERRO: JupyterLab não iniciou."
    echo
    systemctl status "$SERVICE_NAME" --no-pager
    echo
    echo "Logs:"
    journalctl -u "$SERVICE_NAME" -n 50 --no-pager
    exit 1
fi

echo
echo "Porta 8080:"
ss -lntp | grep ':8080' || true

echo
echo "Jupyter:"
systemctl status "$SERVICE_NAME" --no-pager

echo
echo "========================================="
echo " Instalação concluída"
echo "========================================="
echo "VENV: $VENV_PATH"
echo "Jupyter: $VENV_PATH/bin/jupyter"
echo "Porta: 8080"
echo "Usuário: ubuntu"
echo "========================================="