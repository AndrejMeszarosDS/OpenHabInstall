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
  wget -q -O influx.tar.gz https://download.influxdata.com/influxdb/releases/influxdb2-client-2.7.5-linux-arm64.tar.gz
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

log "Login to InfluxDB"

influx config create \
  --config-name temp \
  --host-url http://localhost:8086 \
  --org "$INFLUXDB_ORG" \
  --username-password "$INFLUXDB_USER:$INFLUXDB_PASSWORD" \
  --active 2>/dev/null || true

log "Create InfluxDB token"

INFLUX_TOKEN=$(influx auth create \
  --org "$INFLUXDB_ORG" \
  --description "OpenHAB Token" \
  --all-access \
  --hide-headers | awk 'NR==1 {print $4}')

#--------------------------------------------------------------------------------------------------
log "Configure openHAB Influx"

OPENHAB_INFLUX_CFG="/etc/openhab/services/influxdb.cfg"

sudo tee "$OPENHAB_INFLUX_CFG" > /dev/null <<EOL
version=V2
url=http://localhost:8086
token=$INFLUX_TOKEN
org=$INFLUXDB_ORG
bucket=$INFLUXDB_BUCKET
EOL

sudo chown openhab:openhab "$OPENHAB_INFLUX_CFG"
sudo systemctl restart openhab

#--------------------------------------------------------------------------------------------------
log "System metrics"

HOME_DIR="/home/orangepi"
VENV_DIR="$HOME_DIR/venv"
SYSTEM_METRICS_SCRIPT="$HOME_DIR/system_metrics.py"
INFLUX_URL="http://localhost:8086"

# Install Python
sudo apt-get install -y python3 python3-venv python3-pip

# Create venv (as orangepi!)
if [ ! -d "$VENV_DIR" ]; then
    sudo -u orangepi python3 -m venv "$VENV_DIR"
fi

# Install dependencies (as orangepi!)
sudo -u orangepi "$VENV_DIR/bin/pip" install --upgrade pip
sudo -u orangepi "$VENV_DIR/bin/pip" install influxdb-client psutil

# Create script
cat << EOF > "$SYSTEM_METRICS_SCRIPT"
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
    except:
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

while True:
    try:
        metrics = collect_metrics()
        print(metrics)
        p = Point("system_metrics")
        for k,v in metrics.items():
            if v is not None:
                p = p.field(k, v)
        write_api.write(bucket=bucket, org=org, record=p)
    except Exception as e:
        print("Error:", e)
    time.sleep(10)
EOF

sudo chown orangepi:orangepi "$SYSTEM_METRICS_SCRIPT"
chmod +x "$SYSTEM_METRICS_SCRIPT"

# Create service
sudo tee /etc/systemd/system/system-metrics.service > /dev/null <<EOL
[Unit]
Description=OrangePi System Metrics Collector
After=network-online.target influxdb.service
Wants=network-online.target

[Service]
ExecStart=$VENV_DIR/bin/python $SYSTEM_METRICS_SCRIPT
WorkingDirectory=$HOME_DIR
Restart=always
RestartSec=10
User=orangepi
Environment="PYTHONUNBUFFERED=1"

[Install]
WantedBy=multi-user.target
EOL

# Enable + start
sudo systemctl daemon-reload
sudo systemctl enable system-metrics
sudo systemctl restart system-metrics

#--------------------------------------------------------------------------------------------------
# FIX /tmp AGAIN
sudo chown root:root /tmp
sudo chmod 1777 /tmp

#--------------------------------------------------------------------------------------------------
log "Grafana"

sudo apt-get install -y apt-transport-https software-properties-common wget

if [ ! -f /etc/apt/sources.list.d/grafana.list ]; then
  sudo mkdir -p /etc/apt/keyrings
  wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
  echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | \
  sudo tee /etc/apt/sources.list.d/grafana.list
  sudo apt-get update
fi

if ! dpkg -s grafana &>/dev/null; then
  sudo apt-get install -y grafana
fi

# 🔥 CORRECT ORDER (CRITICAL)
sudo systemctl stop grafana-server || true
sudo rm -rf /var/lib/grafana
sudo mkdir -p /var/lib/grafana /var/log/grafana
sudo chown -R grafana:grafana /var/lib/grafana /var/log/grafana
sudo chmod 755 /var/lib/grafana /var/log/grafana

sudo systemctl start grafana-server
sleep 5

sudo grafana-cli admin reset-admin-password "$GRAFANA_PASSWORD"

#--------------------------------------------------------------------------------------------------
log "Waiting for Grafana"

for i in {1..40}; do
  if curl -s http://localhost:3000 > /dev/null; then
    echo "✅ Grafana is up"
    break
  fi
  sleep 3
done

echo "--------------------------------------------------"
echo "✅ INSTALL COMPLETE"
echo "openHAB: http://<ip>:8080"
echo "Grafana: http://<ip>:3000"
echo "--------------------------------------------------"