#!/usr/bin/env bash
set -euo pipefail

log() { echo -e "\n🔹 $1"; }

#--------------------------------------------------------------------------------------------------

# FIX /tmp (CRITICAL)

#--------------------------------------------------------------------------------------------------
log "Fix /tmp"
sudo mkdir -p /tmp
sudo chown root:root /tmp
sudo chmod 1777 /tmp

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
SAMBA_PASSWORD="secret"

#--------------------------------------------------------------------------------------------------
log "Update system"
sudo apt-get update

#--------------------------------------------------------------------------------------------------
log "Mosquitto"
if ! dpkg -s mosquitto &>/dev/null; then
sudo apt-get install -y mosquitto mosquitto-clients
fi

if [ ! -f /etc/mosquitto/passwd ]; then
sudo mosquitto_passwd -b -c /etc/mosquitto/passwd "$SCRIPT_USER" "$MOSQUITTO_PASSWORD"
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

echo "deb [signed-by=/usr/share/keyrings/openhab.gpg] https://openhab.jfrog.io/artifactory/openhab-linuxpkg stable main" | 
sudo tee /etc/apt/sources.list.d/openhab.list

sudo apt-get update
sudo apt-get install -y openhab
sudo apt-mark hold openhab openhab-addons
fi

sudo systemctl enable openhab
sudo systemctl start openhab

until curl -s http://localhost:8080 > /dev/null; do sleep 5; done

#--------------------------------------------------------------------------------------------------
log "Samba"
if ! dpkg -s samba &>/dev/null; then
sudo apt-get install -y samba samba-common-bin
fi

if [ ! -f /etc/samba/smb.conf ]; then
sudo wget -q -O /etc/samba/smb.conf 
https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/samba/smb.conf
fi

if ! sudo pdbedit -L | grep -q "^$SCRIPT_USER:"; then
(echo "$SAMBA_PASSWORD"; echo "$SAMBA_PASSWORD") | sudo smbpasswd -s -a "$SCRIPT_USER"
fi

sudo usermod -a -G openhab "$SCRIPT_USER"
sudo chmod -R g+w /etc/openhab || true
sudo chmod -R g+w /var/lib/openhab/jsondb || true

sudo systemctl enable smbd
sudo systemctl restart smbd

#--------------------------------------------------------------------------------------------------
log "openHAB user"
if ! sudo openhab-cli console -p habopen "users list" | grep -q "$OPENHAB_ADMIN_USER_NAME"; then
sudo openhab-cli console -p habopen users add 
"$OPENHAB_ADMIN_USER_NAME" 
"$OPENHAB_ADMIN_USER_PASSWORD" 
administrator
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
wget -q -O influx.tar.gz https://download.influxdata.com/influxdb/releases/influxdb2-client-2.7.5-linux-arm64.tar.gz
tar -xzf influx.tar.gz
BIN=$(find . -type f -name influx | head -n1)
sudo cp "$BIN" /usr/local/bin/influx
sudo chmod +x /usr/local/bin/influx
fi

#--------------------------------------------------------------------------------------------------
log "InfluxDB setup"
if ! influx bucket list --org "$INFLUXDB_ORG" >/dev/null 2>&1; then
influx setup --username "$INFLUXDB_USER" \
             --password "$INFLUXDB_PASSWORD" \
             --org "$INFLUXDB_ORG" \
             --bucket "$INFLUXDB_BUCKET" \
             --retention "$INFLUXDB_RETENTION" \
             --force
fi

#--------------------------------------------------------------------------------------------------
log "Create InfluxDB token"

INFLUX_TOKEN=$(influx auth create 
--org "$INFLUXDB_ORG" 
--description "OpenHAB Token" 
--all-access 
--json | grep -o '"token":"[^"]*"' | cut -d':' -f2 | tr -d '"')

if [ -z "$INFLUX_TOKEN" ]; then
echo "❌ Failed to create InfluxDB token"
exit 1
fi

echo "✅ Token created"

#--------------------------------------------------------------------------------------------------
log "Configure openHAB Influx"

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

VENV_DIR="$HOME_DIR/venv"
SCRIPT="$HOME_DIR/system_metrics.py"

sudo apt-get install -y python3 python3-venv python3-pip

if [ ! -d "$VENV_DIR" ]; then
sudo -u "$SCRIPT_USER" python3 -m venv "$VENV_DIR"
fi

sudo -u "$SCRIPT_USER" "$VENV_DIR/bin/pip" install influxdb-client psutil

cat <<EOF > "$SCRIPT"
from influxdb_client import InfluxDBClient, Point
import psutil, time

client = InfluxDBClient(url="http://localhost:8086", token="$INFLUX_TOKEN", org="$INFLUXDB_ORG")
write = client.write_api()

while True:
p = Point("system_metrics")
.field("cpu_percent", psutil.cpu_percent())
.field("mem_percent", psutil.virtual_memory().percent)
write.write(bucket="$INFLUXDB_BUCKET", record=p)
time.sleep(10)
EOF

chmod +x "$SCRIPT"

sudo tee /etc/systemd/system/system-metrics.service > /dev/null <<EOL
[Service]
ExecStart=$VENV_DIR/bin/python $SCRIPT
Restart=always
User=$SCRIPT_USER
EOL

sudo systemctl daemon-reload
sudo systemctl enable system-metrics
sudo systemctl restart system-metrics

#--------------------------------------------------------------------------------------------------
log "Grafana"

sudo apt-get install -y apt-transport-https software-properties-common wget

sudo mkdir -p /etc/apt/keyrings
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | 
sudo tee /etc/apt/sources.list.d/grafana.list

sudo apt-get update
sudo apt-get install -y grafana

sudo systemctl stop grafana-server || true
sudo rm -rf /var/lib/grafana
sudo mkdir -p /var/lib/grafana
sudo chown -R grafana:grafana /var/lib/grafana

sudo systemctl start grafana-server
sleep 5

sudo grafana-cli admin reset-admin-password "$GRAFANA_PASSWORD"

#--------------------------------------------------------------------------------------------------
log "Grafana provisioning"

sudo mkdir -p /etc/grafana/provisioning/datasources
sudo mkdir -p /etc/grafana/provisioning/dashboards
sudo mkdir -p /var/lib/grafana/dashboards

sudo tee /etc/grafana/provisioning/datasources/influxdb.yaml > /dev/null <<EOL
apiVersion: 1
datasources:

* name: InfluxDB
  type: influxdb
  url: http://localhost:8086
  isDefault: true
  jsonData:
  version: Flux
  organization: $INFLUXDB_ORG
  defaultBucket: $INFLUXDB_BUCKET
  secureJsonData:
  token: $INFLUX_TOKEN
  EOL

sudo tee /etc/grafana/provisioning/dashboards/system_metrics.yaml > /dev/null <<EOL
apiVersion: 1
providers:

* name: 'System Metrics'
  type: file
  options:
  path: /var/lib/grafana/dashboards
  EOL

sudo wget -q -O /var/lib/grafana/dashboards/system_metrics.json 
https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/grafana/system_metrics_dashboard.json

sudo chown -R grafana:grafana /var/lib/grafana
sudo systemctl restart grafana-server

#--------------------------------------------------------------------------------------------------
log "DONE"

echo "openHAB: http://<ip>:8080"
echo "Grafana: http://<ip>:3000"
