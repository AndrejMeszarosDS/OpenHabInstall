#!/usr/bin/env bash
set -euo pipefail

log() { echo -e "\n🔹 $1"; }

SCRIPT_USER="${SUDO_USER:-orangepi}"
HOME_DIR="/home/$SCRIPT_USER"

MOSQUITTO_PASSWORD="mqttpass"
OPENHAB_ADMIN_USER_NAME="admin"
OPENHAB_ADMIN_USER_PASSWORD="openhab_password"

INFLUXDB_USER="orangepi"
INFLUXDB_PASSWORD="orangepi"
INFLUXDB_ORG="openhab"
INFLUXDB_BUCKET="openhab"
INFLUXDB_RETENTION="0"

GRAFANA_PASSWORD="grafana_password"

#--------------------------------------------------------------------------------------------------
log "Update system"
sudo apt-get update

#--------------------------------------------------------------------------------------------------
log "Mosquitto"

if ! dpkg -s mosquitto &>/dev/null; then
  sudo apt-get install -y mosquitto mosquitto-clients
fi

if [ ! -f /etc/mosquitto/passwd ]; then
  sudo mosquitto_passwd -b -c /etc/mosquitto/passwd orangepi "$MOSQUITTO_PASSWORD"
fi

sudo systemctl enable mosquitto
sudo systemctl restart mosquitto

#--------------------------------------------------------------------------------------------------
log "Java"

if ! dpkg -s openjdk-21-jre-headless &>/dev/null; then
  sudo apt-get install -y openjdk-21-jre-headless
fi

#--------------------------------------------------------------------------------------------------
log "openHAB install"

if ! dpkg -s openhab &>/dev/null; then
  curl -fsSL https://openhab.jfrog.io/artifactory/api/gpg/key/public | gpg --dearmor > openhab.gpg
  sudo mkdir -p /usr/share/keyrings
  sudo mv openhab.gpg /usr/share/keyrings/openhab.gpg
  sudo chmod 644 /usr/share/keyrings/openhab.gpg

  echo "deb [signed-by=/usr/share/keyrings/openhab.gpg] https://openhab.jfrog.io/artifactory/openhab-linuxpkg stable main" | \
  sudo tee /etc/apt/sources.list.d/openhab.list

  sudo apt-get update
  sudo apt-get install -y openhab
  sudo apt-mark hold openhab openhab-addons
fi

sudo systemctl enable openhab
sudo systemctl start openhab

until curl -s http://localhost:8080 > /dev/null; do sleep 5; done

#--------------------------------------------------------------------------------------------------
log "openHAB user"

if ! sudo openhab-cli console -p habopen "users list" | grep -q "$OPENHAB_ADMIN_USER_NAME"; then
  sudo openhab-cli console -p habopen users add \
  "$OPENHAB_ADMIN_USER_NAME" \
  "$OPENHAB_ADMIN_USER_PASSWORD" \
  administrator
fi

#--------------------------------------------------------------------------------------------------
log "openHAB config"

if [ ! -f /etc/openhab/services/addons.cfg ]; then
  sudo wget -q -O /etc/openhab/services/addons.cfg \
  https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/openhab/addons.cfg
  sudo chown openhab:openhab /etc/openhab/services/addons.cfg
fi

if ! grep -q "org.openhab.persistence:default=influxdb" /etc/openhab/services/runtime.cfg 2>/dev/null; then
  echo "org.openhab.persistence:default=influxdb" | sudo tee -a /etc/openhab/services/runtime.cfg
fi

#--------------------------------------------------------------------------------------------------
log "InfluxDB"

if ! dpkg -s influxdb2 &>/dev/null; then
  curl -LO https://download.influxdata.com/influxdb/releases/influxdb2_2.7.7-1_arm64.deb
  sudo dpkg -i influxdb2_2.7.7-1_arm64.deb
fi

sudo systemctl enable influxdb
sudo systemctl start influxdb

until curl -s http://localhost:8086/health | grep -q '"status":"pass"'; do sleep 3; done

#--------------------------------------------------------------------------------------------------
log "Influx CLI"

if ! command -v influx &>/dev/null; then
  cd /tmp
  wget -O influx.tar.gz https://download.influxdata.com/influxdb/releases/influxdb2-client-2.7.5-linux-arm64.tar.gz
  tar -xzf influx.tar.gz
  BIN=$(find . -type f -name influx | head -n1)
  sudo cp "$BIN" /usr/local/bin/influx
  sudo chmod +x /usr/local/bin/influx
fi

#--------------------------------------------------------------------------------------------------
log "InfluxDB setup"

if ! influx org list >/dev/null 2>&1; then
  influx setup \
    --username "$INFLUXDB_USER" \
    --password "$INFLUXDB_PASSWORD" \
    --org "$INFLUXDB_ORG" \
    --bucket "$INFLUXDB_BUCKET" \
    --retention "$INFLUXDB_RETENTION" \
    --force
fi

#--------------------------------------------------------------------------------------------------
log "Get or create InfluxDB token"

INFLUX_TOKEN=""

if influx auth list >/dev/null 2>&1; then
  INFLUX_TOKEN=$(influx auth list --json | grep -o '"token":"[^"]*"' | head -n1 | cut -d':' -f2 | tr -d '"')
fi

if [ -z "$INFLUX_TOKEN" ]; then
  echo "Creating token..."

  INFLUX_TOKEN=$(influx auth create \
    --org "$INFLUXDB_ORG" \
    --all-access \
    --json | grep -o '"token":"[^"]*"' | cut -d':' -f2 | tr -d '"')
fi

if [ -z "$INFLUX_TOKEN" ]; then
  echo "❌ Failed to obtain InfluxDB token"
  exit 1
fi

echo "✅ Token ready"

#--------------------------------------------------------------------------------------------------
log "Configure Influx CLI"

influx config create \
  --config-name default \
  --host-url http://localhost:8086 \
  --org "$INFLUXDB_ORG" \
  --token "$INFLUX_TOKEN" \
  --active 2>/dev/null || true