#!/bin/bash
# =============================================================================
# Setup do Servidor Dedicado — TribalLine
# Testado em Ubuntu 22.04 / Debian 12
# =============================================================================
# Uso:
#   chmod +x setup_server.sh
#   sudo ./setup_server.sh
# =============================================================================

set -e

GAME_USER="triballine"
GAME_DIR="/opt/triballine"
PORT=7777
SERVICE_NAME="triballine"

echo "======================================================"
echo " TribalLine — Configurando Servidor Dedicado"
echo "======================================================"

# 1. Instalar dependencias
echo "[1/6] Instalando dependencias..."
apt-get update -qq
apt-get install -y -qq wget unzip ufw screen

# 2. Criar usuario dedicado
echo "[2/6] Criando usuario '$GAME_USER'..."
if ! id "$GAME_USER" &>/dev/null; then
    useradd -r -s /bin/false -d "$GAME_DIR" "$GAME_USER"
fi

# 3. Criar diretorio
echo "[3/6] Configurando diretorio '$GAME_DIR'..."
mkdir -p "$GAME_DIR"
chown "$GAME_USER:$GAME_USER" "$GAME_DIR"

# 4. Abrir porta no firewall
echo "[4/6] Abrindo porta UDP $PORT no firewall..."
ufw allow "$PORT/udp" comment "TribalLine"
ufw --force enable

# 5. Criar servico systemd
echo "[5/6] Criando servico systemd '$SERVICE_NAME'..."
cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=TribalLine Dedicated Server
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=$GAME_USER
WorkingDirectory=$GAME_DIR
ExecStart=$GAME_DIR/triballine.x86_64 --headless -- --server --port $PORT
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME
# Limite de memoria (ajustar conforme RAM do VPS)
MemoryLimit=512M

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"

# 6. Instrucoes finais
echo "[6/6] Configuracao concluida!"
echo ""
echo "======================================================"
echo " PROXIMOS PASSOS:"
echo "======================================================"
echo ""
echo " 1. Copie o executavel exportado para o servidor:"
echo "    scp triballine.x86_64 usuario@SEU_IP:$GAME_DIR/"
echo "    scp triballine.pck    usuario@SEU_IP:$GAME_DIR/"
echo ""
echo " 2. Defina permissao de execucao:"
echo "    chmod +x $GAME_DIR/triballine.x86_64"
echo "    chown -R $GAME_USER:$GAME_USER $GAME_DIR"
echo ""
echo " 3. Inicie o servidor:"
echo "    sudo systemctl start $SERVICE_NAME"
echo ""
echo " 4. Veja os logs:"
echo "    sudo journalctl -u $SERVICE_NAME -f"
echo ""
echo " 5. Verificar status:"
echo "    sudo systemctl status $SERVICE_NAME"
echo ""
echo " Porta UDP $PORT deve estar aberta no firewall do VPS."
echo " (Verifique tambem o painel do provedor: AWS/DigitalOcean/etc)"
echo "======================================================"
