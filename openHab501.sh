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

  FILE="influxdb2-client.tar.gz"
  URL="https://download.influxdata.com/influxdb/releases/influxdb2-client-2.7.5-linux-arm64.tar.gz"

  wget -O "$FILE" "$URL"
  tar -xzf "$FILE"

  BIN=$(find . -type f -name influx | head -n1)

  if [ -z "$BIN" ]; then
    echo "❌ ERROR: influx binary not found"
    exit 1
  fi

  sudo cp "$BIN" /usr/local/bin/influx
  sudo chmod +x /usr/local/bin/influx
fi

#--------------------------------------------------------------------------------------------------
log "InfluxDB setup"

if ! influx org list 2>/dev/null | grep -q "$INFLUXDB_ORG"; then
  influx setup \
    --username "$INFLUXDB_USER" \
    --password "$INFLUXDB_PASSWORD" \
    --org "$INFLUXDB_ORG" \
    --bucket "$INFLUXDB_BUCKET" \
    --retention "$INFLUXDB_RETENTION" \
    --force
fi

influx config create \
  --config-name default \
  --host-url http://localhost:8086 \
  --org "$INFLUXDB_ORG" \
  --username "$INFLUXDB_USER" \
  --password "$INFLUXDB_PASSWORD" \
  --active 2>/dev/null || true

#--------------------------------------------------------------------------------------------------
log "Get or create InfluxDB token"

INFLUX_TOKEN=$(influx auth list --json 2>/dev/null | grep -o '"token":"[^"]*"' | head -n1 | cut -d':' -f2 | tr -d '"')

if [ -z "${INFLUX_TOKEN:-}" ]; then
  INFLUX_TOKEN=$(influx auth create \
    --org "$INFLUXDB_ORG" \
    --all-access \
    --json | grep -o '"token":"[^"]*"' | cut -d':' -f2 | tr -d '"')

  if [ -z "$INFLUX_TOKEN" ]; then
    echo "❌ Failed to create InfluxDB token"
    exit 1
  fi
fi

#--------------------------------------------------------------------------------------------------
log "Configure openHAB influx"

sudo tee /etc/openhab/services/influxdb.cfg > /dev/null <<EOL
version=V2
url=http://localhost:8086
token=$INFLUX_TOKEN
org=$INFLUXDB_ORG
bucket=$INFLUXDB_BUCKET
EOL

sudo systemctl restart openhab

#--------------------------------------------------------------------------------------------------
log "System metrics"

sudo apt-get install -y python3 python3-venv python3-pip

VENV_DIR="$HOME_DIR/venv"
SCRIPT_PATH="$HOME_DIR/system_metrics.py"

if [ ! -d "$VENV_DIR" ]; then
  sudo -u $SCRIPT_USER python3 -m venv "$VENV_DIR"
  sudo -u $SCRIPT_USER "$VENV_DIR/bin/pip" install influxdb-client psutil
fi

cat <<EOF > "$SCRIPT_PATH"
import psutil,time
from influxdb_client import InfluxDBClient,Point
c=InfluxDBClient(url="http://localhost:8086",token="$INFLUX_TOKEN",org="$INFLUXDB_ORG")
w=c.write_api()
while True:
 p=Point("system").field("cpu",psutil.cpu_percent()).field("mem",psutil.virtual_memory().percent)
 w.write(bucket="$INFLUXDB_BUCKET",record=p)
 time.sleep(10)
EOF

chmod +x "$SCRIPT_PATH"

if [ ! -f /etc/systemd/system/system-metrics.service ]; then
sudo tee /etc/systemd/system/system-metrics.service > /dev/null <<EOL
[Unit]
After=network-online.target influxdb.service
Wants=network-online.target
[Service]
ExecStart=$VENV_DIR/bin/python $SCRIPT_PATH
Restart=always
User=$SCRIPT_USER
[Install]
WantedBy=multi-user.target
EOL
fi

sudo systemctl daemon-reload
sudo systemctl enable system-metrics
sudo systemctl restart system-metrics

#--------------------------------------------------------------------------------------------------
log "Grafana"

if ! dpkg -s grafana &>/dev/null; then
  sudo mkdir -p /etc/apt/keyrings
  wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
  echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | \
  sudo tee /etc/apt/sources.list.d/grafana.list
  sudo apt-get update
  sudo apt-get install -y grafana
fi

sudo grafana-cli admin reset-admin-password "$GRAFANA_PASSWORD"

sudo systemctl enable grafana-server
sudo systemctl start grafana-server

until curl -s http://localhost:3000 > /dev/null; do sleep 3; done

#--------------------------------------------------------------------------------------------------
log "Grafana provisioning"

sudo mkdir -p /etc/grafana/provisioning/datasources
sudo mkdir -p /etc/grafana/provisioning/dashboards
sudo mkdir -p /var/lib/grafana/dashboards

if [ ! -f /etc/grafana/provisioning/datasources/influxdb.yaml ]; then
sudo tee /etc/grafana/provisioning/datasources/influxdb.yaml > /dev/null <<EOL
apiVersion: 1
datasources:
- name: InfluxDB
  type: influxdb
  url: http://localhost:8086
  jsonData:
    version: Flux
    organization: $INFLUXDB_ORG
    defaultBucket: $INFLUXDB_BUCKET
  secureJsonData:
    token: $INFLUX_TOKEN
  isDefault: true
EOL
fi

if [ ! -f /var/lib/grafana/dashboards/system.json ]; then
  sudo wget -q -O /var/lib/grafana/dashboards/system.json \
  https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/grafana/system_metrics_dashboard.json
fi

sudo chown -R grafana:grafana /var/lib/grafana
sudo systemctl restart grafana-server

#--------------------------------------------------------------------------------------------------
log "DONE"

echo "openHAB: http://<ip>:8080"
echo "Grafana: http://<ip>:3000"