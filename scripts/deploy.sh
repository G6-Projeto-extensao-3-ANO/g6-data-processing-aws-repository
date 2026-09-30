#!/bin/bash

VENV_NAME="amb"
SERVICE_NAME="jupyterlab"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
MY_PASSWD="urubu100"
USER_HOME="/home/ubuntu"
CURRENT_USER="ubuntu"

echo "Configurando o ambiente"

sudo apt update && sudo apt upgrade -y
sudo apt install python3-pip python3-venv -y
python3 -m venv $VENV_NAME --prompt=jupter
source $VENV_NAME/bin/activate
pip install --upgrade pip
pip install jupyterlab pyspark findspark


echo "Criando o arquivo de config Jupyter"
HASH_PASSWD=$(python3 -c "from jupyter_server.auth import passwd; print(passwd('$MY_PASSWD'))")

mkdir -p $USER_HOME/.jupyter

cat <<EOF > $USER_HOME/.jupyter/jupyter_lab_config.py
c.ServerApp.ip = '0.0.0.0'
c.ServerApp.port = 8080
c.ServerApp.open_browser = False
c.ServerApp.identity_provider_class = 'jupyter_server.auth.identity.PasswordIdentityProvider'
c.PasswordIdentityProvider.hashed_password = '$HASH_PASSWD'
EOF


echo "Criando o arquivo de serviço systemd..."

# O comando 'sudo tee' escreve no caminho especificado mantendo as permissões de root
sudo tee $SERVICE_PATH > /dev/null <<EOF
[Unit]
Description=JupyterLab
[Service]
Type=simple
PIDFile=/run/jupyterlab.pid
ExecStart=/home/ubuntu/$VENV_NAME/bin/jupyter lab --config=$USER_HOME/.jupyter/jupyter_lab_config.py
User=ubuntu
Group=ubuntu
WorkingDirectory=/home/ubuntu
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF

echo "Arquivo $SERVICE_PATH criado com sucesso!"

# Recarrega as configurações do systemd para reconhecer o novo serviço
sudo systemctl daemon-reload

# Habilita o serviço para iniciar no boot e inicia imediatamente
sudo systemctl enable $SERVICE_NAME
sudo systemctl start $SERVICE_NAME

echo "Serviço $SERVICE_NAME ativado e iniciado!"