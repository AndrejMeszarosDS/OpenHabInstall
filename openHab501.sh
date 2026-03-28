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

# Ensure InfluxDB is reachable
until curl -s http://localhost:8086/health | grep -q '"status":"pass"'; do
  sleep 3
done

# If not initialized, run setup
if ! influx org list >/dev/null 2>&1; then
  echo "Running initial setup..."

  influx setup \
    --username "$INFLUXDB_USER" \
    --password "$INFLUXDB_PASSWORD" \
    --org "$INFLUXDB_ORG" \
    --bucket "$INFLUXDB_BUCKET" \
    --retention "$INFLUXDB_RETENTION" \
    --force
fi

#--------------------------------------------------------------------------------------------------
log "Login to InfluxDB (CLI)"

# force login using username/password
influx config create \
  --config-name temp \
  --host-url http://localhost:8086 \
  --org "$INFLUXDB_ORG" \
  --username-password "$INFLUXDB_USER:$INFLUXDB_PASSWORD" \
  --active 2>/dev/null || true

#--------------------------------------------------------------------------------------------------
log "Create InfluxDB token"

INFLUX_TOKEN=$(sudo influx auth create \
    --org "$INFLUXDB_ORG" \
    --description "OpenHAB Token" \
    --all-access \
    --hide-headers | awk 'NR==1 {print $4}')

if [ -z "$INFLUX_TOKEN" ] || [ "$INFLUX_TOKEN" == "Error" ]; then
    echo "Failed to create InfluxDB token. Verify your InfluxDB setup and credentials."
    exit 1
fi

echo "✅ Token created: $INFLUX_TOKEN"

#--------------------------------------------------------------------------------------------------
log "Configure openHAB to use InfluxDB"

OPENHAB_INFLUX_CFG="/etc/openhab/services/influxdb.cfg"

# Create file if missing
if [ ! -f "$OPENHAB_INFLUX_CFG" ]; then
    echo "Creating InfluxDB config file..."
    sudo touch "$OPENHAB_INFLUX_CFG"
fi

# Backup only once
if [ ! -f "$OPENHAB_INFLUX_CFG.bak" ]; then
    sudo cp "$OPENHAB_INFLUX_CFG" "$OPENHAB_INFLUX_CFG.bak"
fi

# Write config
sudo tee "$OPENHAB_INFLUX_CFG" > /dev/null <<EOL
# OpenHAB InfluxDB Configuration
version=V2
url=http://localhost:8086
token=$INFLUX_TOKEN
org=$INFLUXDB_ORG
bucket=$INFLUXDB_BUCKET
retentionPolicy=$INFLUXDB_BUCKET
EOL

# Fix ownership
sudo chown openhab:openhab "$OPENHAB_INFLUX_CFG"

# Restart openHAB to apply changes
sudo systemctl restart openhab

echo "✅ OpenHAB configured to use InfluxDB"

#--------------------------------------------------------------------------------------------------
log "System metrics"

VENV_DIR="$HOME_DIR/venv"
SYSTEM_METRICS_SCRIPT="$HOME_DIR/system_metrics.py"
INFLUX_URL="http://localhost:8086"

# Install Python deps (safe)
sudo apt-get install -y python3 python3-venv python3-pip

# Create virtualenv (as user)
if [ ! -d "$VENV_DIR" ]; then
    sudo -u "$SCRIPT_USER" python3 -m venv "$VENV_DIR"
fi

# Install Python packages (only if missing)
if ! sudo -u "$SCRIPT_USER" "$VENV_DIR/bin/pip" show influxdb-client >/dev/null 2>&1; then
    sudo -u "$SCRIPT_USER" "$VENV_DIR/bin/pip" install --upgrade pip
    sudo -u "$SCRIPT_USER" "$VENV_DIR/bin/pip" install influxdb-client psutil
fi

# Create metrics script
cat <<EOF > "$SYSTEM_METRICS_SCRIPT"
#!/usr/bin/env python3
import psutil, time
from influxdb_client import InfluxDBClient, Point, WriteOptions

url = "$INFLUX_URL"
token = "$INFLUX_TOKEN"
org = "$INFLUXDB_ORG"
bucket = "$INFLUXDB_BUCKET"

client = InfluxDBClient(url=url, token=token, org=org)
write_api = client.write_api(write_options=WriteOptions(batch_size=1))

def read_temp(path):
    try:
        with open(path, "r") as f:
            return int(f.read().strip()) / 1000.0
    except FileNotFoundError:
        return None

def collect_metrics():
    record = {}
    record["cpu_percent"] = psutil.cpu_percent(interval=1)

    per_core = psutil.cpu_percent(interval=None, percpu=True)
    for i, usage in enumerate(per_core):
        record[f"cpu_core{i}_percent"] = usage

    mem = psutil.virtual_memory()
    record["mem_total_mb"] = mem.total / 1024 / 1024
    record["mem_used_mb"] = mem.used / 1024 / 1024
    record["mem_percent"] = mem.percent

    record["load1"], record["load5"], record["load15"] = psutil.getloadavg()

    record["cpu_temp"] = read_temp("/sys/class/thermal/thermal_zone0/temp")
    record["ddr_temp"] = read_temp("/sys/class/thermal/thermal_zone1/temp")
    record["gpu_temp"] = read_temp("/sys/class/thermal/thermal_zone2/temp")
    record["ve_temp"]  = read_temp("/sys/class/thermal/thermal_zone3/temp")

    return record

if __name__ == "__main__":
    while True:
        try:
            metrics = collect_metrics()
            p = Point("system_metrics")
            for k,v in metrics.items():
                if v is not None:
                    p = p.field(k, v)
            write_api.write(bucket=bucket, org=org, record=p)
        except Exception as e:
            print("Error:", e)
        time.sleep(10)
EOF

# Permissions
sudo chown "$SCRIPT_USER":"$SCRIPT_USER" "$SYSTEM_METRICS_SCRIPT"
chmod +x "$SYSTEM_METRICS_SCRIPT"

#--------------------------------------------------------------------------------------------------
log "System metrics service"

SERVICE_FILE="/etc/systemd/system/system-metrics.service"

if [ ! -f "$SERVICE_FILE" ]; then
sudo tee "$SERVICE_FILE" > /dev/null <<EOL
[Unit]
Description=OrangePi System Metrics Collector
After=network-online.target influxdb.service
Wants=network-online.target

[Service]
ExecStart=$VENV_DIR/bin/python $SYSTEM_METRICS_SCRIPT
WorkingDirectory=$HOME_DIR
Restart=always
RestartSec=10
User=$SCRIPT_USER
Environment="PYTHONUNBUFFERED=1"

[Install]
WantedBy=multi-user.target
EOL
fi

sudo systemctl daemon-reload
sudo systemctl enable system-metrics.service
sudo systemctl restart system-metrics.service

echo "✅ System metrics service running"

#--------------------------------------------------------------------------------------------------
log "Grafana"

# Install dependencies (safe)
sudo apt-get install -y apt-transport-https software-properties-common wget

# Add Grafana repo ONLY once
if [ ! -f /etc/apt/sources.list.d/grafana.list ]; then
  sudo mkdir -p /etc/apt/keyrings
  wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
  echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | \
  sudo tee /etc/apt/sources.list.d/grafana.list
  sudo apt-get update
fi

# Install Grafana only if missing
if ! dpkg -s grafana &>/dev/null; then
  sudo apt-get install -y grafana
fi

# Fix ONLY required permissions (safe)
sudo chown -R grafana:grafana /var/lib/grafana
sudo chown -R grafana:grafana /var/log/grafana

# Reset admin password
sudo grafana-cli admin reset-admin-password "$GRAFANA_PASSWORD"

# Enable + start service
sudo systemctl daemon-reload
sudo systemctl enable grafana-server
sudo systemctl restart grafana-server

#--------------------------------------------------------------------------------------------------
log "Waiting for Grafana"

for i in {1..40}; do
  if curl -s http://localhost:3000 > /dev/null; then
    echo "✅ Grafana is up"
    break
  fi
  sleep 3
done

if ! curl -s http://localhost:3000 > /dev/null; then
  echo "⚠️ Grafana failed to start"
  systemctl status grafana-server --no-pager
fi

#--------------------------------------------------------------------------------------------------
log "Grafana provisioning"

GRAFANA_PROVISIONING_DIR="/etc/grafana/provisioning"
INFLUXDB_URL="http://localhost:8086"

# Create directories
sudo mkdir -p "$GRAFANA_PROVISIONING_DIR/datasources"
sudo mkdir -p "$GRAFANA_PROVISIONING_DIR/dashboards"
sudo mkdir -p /var/lib/grafana/dashboards

#--------------------------------------------------------------------------------------------------
# InfluxDB datasource (only once)
if [ ! -f "$GRAFANA_PROVISIONING_DIR/datasources/influxdb.yaml" ]; then
sudo tee "$GRAFANA_PROVISIONING_DIR/datasources/influxdb.yaml" > /dev/null <<EOL
apiVersion: 1
datasources:
  - name: InfluxDB
    type: influxdb
    access: proxy
    url: $INFLUXDB_URL
    jsonData:
      version: Flux
      organization: $INFLUXDB_ORG
      defaultBucket: $INFLUXDB_BUCKET
    secureJsonData:
      token: $INFLUX_TOKEN
    isDefault: true
EOL
fi

#--------------------------------------------------------------------------------------------------
# Dashboard provider (only once)
if [ ! -f "$GRAFANA_PROVISIONING_DIR/dashboards/system_metrics.yaml" ]; then
sudo tee "$GRAFANA_PROVISIONING_DIR/dashboards/system_metrics.yaml" > /dev/null <<EOL
apiVersion: 1
providers:
  - name: 'System Metrics'
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    options:
      path: /var/lib/grafana/dashboards
EOL
fi

#--------------------------------------------------------------------------------------------------
# Dashboard JSON (only once)
if [ ! -f /var/lib/grafana/dashboards/system_metrics.json ]; then
  sudo wget -q -O /var/lib/grafana/dashboards/system_metrics.json \
  https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/grafana/system_metrics_dashboard.json
fi

# Fix ownership
sudo chown -R grafana:grafana /var/lib/grafana/dashboards

# Restart Grafana to load provisioning
sudo systemctl restart grafana-server

echo "✅ Grafana fully configured"
echo "👉 http://<your-ip>:3000  (admin / $GRAFANA_PASSWORD)"