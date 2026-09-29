#!/bin/bash

set -e

echo "========================================"
echo " DEPLOY DA APLICAÇÃO"
echo "========================================"

APP_DIR="/opt/app"

echo ""
echo "[1/4] Verificando diretório da aplicação..."

mkdir -p "$APP_DIR"


echo ""
echo "[2/4] Preparando aplicação..."

cd "$APP_DIR"


echo ""
echo "[3/4] Verificando Docker..."

docker --version
docker compose version


echo ""
echo "[4/4] Executando aplicação..."

docker compose up -d --build


echo ""
echo "========================================"
echo " DEPLOY CONCLUÍDO"
echo "========================================"

docker compose ps