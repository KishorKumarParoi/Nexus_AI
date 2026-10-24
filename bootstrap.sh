#!/usr/bin/env bash
# ==============================================================================
# 🚀 ZERO-TOUCH 1-COMMAND AUTO-BOOTSTRAPPER FOR EC2 & CLOUD VMS
# NEXUS-AI: ENTERPRISE MULTI-CLOUD LAKEHOUSE & AUTONOMOUS AGENT MESH
#
# Run directly on any bare EC2 instance or cloud VM:
#   curl -fsSL https://raw.githubusercontent.com/KishorKumarParoi/Nexus_AI/main/bootstrap.sh | bash
# ==============================================================================
set -eo pipefail

BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
cat << "EOF"
================================================================================
  ⚡ NEXUS-AI: ENTERPRISE LAKEHOUSE & 5-AGENT MESH — ZERO-TOUCH BOOTSTRAPPER
================================================================================
EOF
echo -e "${NC}"

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export UCF_FORCE_CONFFOLD=1

run_sudo() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    elif command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
        sudo -E "$@"
    elif command -v sudo &>/dev/null; then
        sudo -E "$@"
    else
        "$@"
    fi
}

# 1. Prereqs
echo -e "${CYAN}[1/6] Detecting OS and ensuring Git & Curl are available...${NC}"
if ! command -v git &>/dev/null || ! command -v curl &>/dev/null; then
    if [ -f /etc/debian_version ]; then
        run_sudo apt-get update -qq
        run_sudo apt-get install -y -qq git curl ca-certificates tar gzip unzip build-essential >/dev/null 2>&1
    elif [ -f /etc/amazon-linux-release ] || [ -f /etc/redhat-release ]; then
        run_sudo yum install -y -q git curl ca-certificates tar gzip unzip >/dev/null 2>&1 || true
    fi
fi

# 2. OOM Protection (4GB Swap)
echo -e "\n${CYAN}[2/6] Checking System Memory & OOM Protection...${NC}"
if command -v free &>/dev/null; then
    TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    EXISTING_SWAP_MB=$(free -m | awk '/^Swap:/{print $2}')
    if [ "$TOTAL_RAM_MB" -lt 8000 ] && [ "$EXISTING_SWAP_MB" -lt 2000 ]; then
        echo -e "${YELLOW}[!] Host has ${TOTAL_RAM_MB}MB RAM. Auto-configuring 4GB swapfile for compilation safety...${NC}"
        if [ ! -f /swapfile ]; then
            run_sudo fallocate -l 4G /swapfile 2>/dev/null || run_sudo dd if=/dev/zero of=/swapfile bs=1M count=4096 2>/dev/null
            run_sudo chmod 600 /swapfile
            run_sudo mkswap /swapfile >/dev/null 2>&1
            run_sudo swapon /swapfile 2>/dev/null || true
            run_sudo sysctl vm.swappiness=20 >/dev/null 2>&1 || true
            if ! grep -q "/swapfile" /etc/fstab 2>/dev/null; then
                echo "/swapfile none swap sw 0 0" | run_sudo tee -a /etc/fstab >/dev/null 2>&1 || true
            fi
            echo -e "${GREEN}[✓] 4GB Swapfile configured and active!${NC}"
        fi
    fi
fi

# 3. Clone / Sync
echo -e "\n${CYAN}[3/6] Ensuring Nexus_AI repository is local...${NC}"
REPO_URL="https://github.com/KishorKumarParoi/Nexus_AI.git"
REPO_DIR="Nexus_AI"

if [ -f "docker-compose.yml" ] && [ -f "run_all.sh" ]; then
    echo -e "${GREEN}[✓] Already inside repository directory ($(pwd)). Syncing latest commit...${NC}"
    git pull origin main 2>/dev/null || true
elif [ -d "$REPO_DIR" ]; then
    cd "$REPO_DIR"
    git pull origin main 2>/dev/null || true
else
    echo -e "${YELLOW}[+] Shallow cloning repository from GitHub...${NC}"
    git clone --depth 1 "$REPO_URL" "$REPO_DIR"
    cd "$REPO_DIR"
fi

chmod +x bootstrap.sh clear.sh run_all.sh 2>/dev/null || true

# 4. Public IP & Environment
echo -e "\n${CYAN}[4/6] Discovering Host Public IP & Configuring Environment...${NC}"
SERVER_PUBLIC_IP=""
IMDS_TOKEN=$(curl -s -m 2 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || true)
if [ -n "$IMDS_TOKEN" ]; then
    SERVER_PUBLIC_IP=$(curl -s -m 2 -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" "http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || true)
fi
if [ -z "$SERVER_PUBLIC_IP" ]; then
    SERVER_PUBLIC_IP=$(curl -s -m 3 https://ifconfig.me 2>/dev/null || echo "127.0.0.1")
fi
export SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP:-127.0.0.1}"
echo -e "${GREEN}[✓] Host Public IP Detected: ${BOLD}${SERVER_PUBLIC_IP}${NC}"

if [ ! -f .env ] && [ -f .env.example ]; then
    cp .env.example .env
fi

# 5. Docker Bootstrap
echo -e "\n${CYAN}[5/6] Bootstrapping Docker runtime & Docker Compose...${NC}"
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | run_sudo sh
fi
if [[ "$OSTYPE" != "darwin"* ]]; then
    run_sudo systemctl enable --now docker 2>/dev/null || run_sudo service docker start 2>/dev/null || true
    run_sudo usermod -aG docker "$USER" 2>/dev/null || true
fi

COMPOSE_CMD="docker compose"
if ! docker compose version &>/dev/null; then
    if run_sudo docker compose version &>/dev/null; then
        COMPOSE_CMD="run_sudo docker compose"
    elif command -v docker-compose &>/dev/null; then
        COMPOSE_CMD="docker-compose"
    fi
fi

export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

echo -e "\n${CYAN}[6/6] Launching Nexus-AI Stack...${NC}"
$COMPOSE_CMD up -d --build

# Health check
echo -e "\n${CYAN}[*] Polling Service Health Status...${NC}"
for i in {1..20}; do
    if curl -fs -m 2 "http://localhost:3001" &>/dev/null || curl -fs -m 2 "http://localhost:8081/health" &>/dev/null; then
        echo -e "  ${GREEN}✔${NC} Nexus-AI Services operational"
        break
    fi
    sleep 3
done

echo -e "\n${GREEN}${BOLD}"
cat << "EOF"
================================================================================
🎉 DEPLOYMENT COMPLETE! NEXUS-AI PLATFORM IS LIVE!
================================================================================
EOF
echo -e "${NC}"
echo -e "${BOLD}Enterprise Service Endpoints:${NC}"
echo -e "  ⚛️  Next.js 16 Glassmorphic Cockpit: ${CYAN}http://${SERVER_PUBLIC_IP}:3001${NC}"
echo -e "  🧠 FastAPI Inference Core        : ${CYAN}http://${SERVER_PUBLIC_IP}:8081/docs${NC}"
echo -e "  🌐 Go API Gateway / BFF           : ${CYAN}http://${SERVER_PUBLIC_IP}:3000${NC}"
echo -e "  📊 Prometheus & Grafana           : ${CYAN}http://${SERVER_PUBLIC_IP}:3002${NC}"
echo ""
echo -e "${BOLD}Principal Operations:${NC}"
echo -e "  • Stop & Zero-Cost Teardown: ${YELLOW}./clear.sh${NC}\n"
