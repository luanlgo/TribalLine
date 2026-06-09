# Como Exportar e Subir o Servidor

## Passo 1 — Instalar o template de servidor no Godot

No Godot Editor:
1. Editor > Export...
2. Add Preset → **Linux** (x86_64)
3. Marcar **"Export as Dedicated Server"** (isso desativa toda renderização)
4. Em "Export Path": `triballine.x86_64`
5. Clicar **Export PCK/ZIP** (só o .pck) ou **Export Project**

> Se não aparecer "Dedicated Server": baixar os export templates em
> Editor > Manage Export Templates > Download

---

## Passo 2 — VPS recomendados (custo/benefício)

| Provedor | Plano mínimo | Preço ~| RAM | CPU |
|---|---|---|---|---|
| **Hetzner** (melhor custo) | CX11 | €4/mês | 2GB | 1 vCPU |
| **DigitalOcean** | Droplet Basic | $6/mês | 1GB | 1 vCPU |
| **Contabo** | VPS S | €5/mês | 8GB | 4 vCPU |
| **AWS Lightsail** | Nano | $5/mês | 1GB | 2 vCPU |

> Para começar: **Hetzner CX11** é suficiente para 50-100 jogadores.
> Ubuntu 22.04 LTS.

---

## Passo 3 — Upload dos arquivos

```bash
# Do seu PC Windows (PowerShell):
scp triballine.x86_64  root@SEU_IP:/opt/triballine/
scp triballine.pck     root@SEU_IP:/opt/triballine/

# No servidor:
chmod +x /opt/triballine/triballine.x86_64
chown -R triballine:triballine /opt/triballine/
```

---

## Passo 4 — Iniciar

```bash
sudo systemctl start triballine
sudo systemctl status triballine   # checar se rodou
sudo journalctl -u triballine -f   # ver logs em tempo real
```

---

## Passo 5 — Configurar IP no cliente

No `MainMenu.tscn`, campo **"IP do Servidor"**:
- Colocar o IP público do VPS (ex: `185.199.108.153`)
- Porta padrão: `7777`

---

## Dados persistentes no servidor

Os arquivos ficam em `~/.local/share/godot/app_userdata/TribalLine/`:
- `triballine_save.json` — aldeias de todos os jogadores
- `accounts.json` — contas (username + hash SHA-256 da senha)

```bash
# Fazer backup manual:
cp ~/.local/share/godot/app_userdata/TribalLine/triballine_save.json ./backup_$(date +%Y%m%d).json
```

---

## Regras de firewall necessárias

```bash
# Apenas a porta do jogo (UDP)
ufw allow 7777/udp

# SSH para administração (já deve estar aberto)
ufw allow 22/tcp
```

---

## Teste rápido sem VPS (localhost)

```bash
# Terminal 1 — servidor headless local:
./triballine.x86_64 --headless -- --server

# Terminal 2+ — clientes:
# Abrir o Godot normalmente e conectar em 127.0.0.1:7777
```
