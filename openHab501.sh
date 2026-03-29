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
GRAFANA_ONLY_TEST="${GRAFANA_ONLY_TEST:-0}"

#--------------------------------------------------------------------------------------------------
if [ "$GRAFANA_ONLY_TEST" != "1" ]; then
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
sudo wget -q -O /etc/samba/smb.conf \
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

INFLUX_TOKEN=$(sudo ./influx auth create \
    --org "$INFLUXDB_ORG" \
    --description "OpenHAB Token" \
    --all-access \
    --hide-headers | awk 'NR==1 {print $4}')

if [ -z "$INFLUX_TOKEN" ] || [ "$INFLUX_TOKEN" == "Error" ]; then
    echo "Failed to create InfluxDB token. Verify your InfluxDB setup and credentials."
    exit 1
fi
echo "Token successfully created: $INFLUX_TOKEN"

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
SYSTEM_METRICS_SCRIPT="$HOME_DIR/system_metrics.py"
INFLUX_URL="http://localhost:8086"

sudo apt-get update
sudo apt-get install -y python3 python3-venv python3-pip

if [ ! -d "$VENV_DIR" ]; then
sudo -u "$SCRIPT_USER" python3 -m venv "$VENV_DIR"
fi

sudo -u "$SCRIPT_USER" "$VENV_DIR/bin/pip" install --upgrade pip
sudo -u "$SCRIPT_USER" "$VENV_DIR/bin/pip" install influxdb-client psutil

cat <<EOF > "$SYSTEM_METRICS_SCRIPT"
#!/usr/bin/env python3
import psutil
import time
from influxdb_client import InfluxDBClient, Point, WriteOptions

url = "$INFLUX_URL"
token = "$INFLUX_TOKEN"
org = "$INFLUXDB_ORG"
bucket = "$INFLUXDB_BUCKET"

client = InfluxDBClient(url=url, token=token, org=org)
write_api = client.write_api(write_options=WriteOptions(batch_size=1))


def read_temp(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
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
    record["ve_temp"] = read_temp("/sys/class/thermal/thermal_zone3/temp")

    return record


if __name__ == "__main__":
    while True:
        try:
            metrics = collect_metrics()
            print(metrics)
            p = Point("system_metrics")
            for k, v in metrics.items():
                if v is not None:
                    p = p.field(k, v)
            write_api.write(bucket=bucket, org=org, record=p)
        except Exception as e:
            print("Error:", e)
        time.sleep(10)
EOF

chmod +x "$SYSTEM_METRICS_SCRIPT"

sudo tee /etc/systemd/system/system-metrics.service > /dev/null <<EOL
[Unit]
Description=OrangePi System Metrics Collector
After=network.target influxdb.service

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

sudo systemctl daemon-reload
sudo systemctl enable system-metrics.service
sudo systemctl restart system-metrics.service
sudo systemctl status system-metrics.service || true
fi

#--------------------------------------------------------------------------------------------------
log "Fix /tmp (before Grafana)"

sudo chmod 1777 /tmp
sudo chown root:root /tmp

#--------------------------------------------------------------------------------------------------
log "Grafana"

if [ "$GRAFANA_ONLY_TEST" = "1" ]; then
INFLUX_TOKEN="${INFLUX_TOKEN:-$(sudo awk -F= '/^token=/{print $2}' /etc/openhab/services/influxdb.cfg 2>/dev/null || true)}"
if [ -z "${INFLUX_TOKEN:-}" ]; then
echo "Grafana-only test requires an existing InfluxDB token in /etc/openhab/services/influxdb.cfg"
exit 1
fi
fi

sudo apt-get install -y apt-transport-https software-properties-common wget

sudo mkdir -p /etc/apt/keyrings
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | 
sudo tee /etc/apt/sources.list.d/grafana.list

sudo apt-get update
sudo apt-get install -y grafana

sudo systemctl stop grafana-server || true
sudo systemctl daemon-reload
sudo systemctl enable grafana-server
sudo mkdir -p /var/lib/grafana
sudo chown -R grafana:grafana /var/lib/grafana

sudo systemctl start grafana-server
until curl -fsS http://localhost:3000/api/health > /dev/null; do sleep 3; done

#--------------------------------------------------------------------------------------------------
log "Grafana provisioning"

sudo mkdir -p /etc/grafana/provisioning/datasources
sudo mkdir -p /etc/grafana/provisioning/dashboards
sudo mkdir -p /var/lib/grafana/dashboards

#--------------------------------------------------------------------------------------------------
# Datasource
sudo tee /etc/grafana/provisioning/datasources/influxdb.yaml > /dev/null <<EOL
apiVersion: 1
datasources:
  - name: InfluxDB
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

#--------------------------------------------------------------------------------------------------
# Dashboard provider
sudo tee /etc/grafana/provisioning/dashboards/system_metrics.yaml > /dev/null <<EOL
apiVersion: 1
providers:
  - name: 'System Metrics'
    type: file
    options:
      path: /var/lib/grafana/dashboards
EOL

#--------------------------------------------------------------------------------------------------
# Download dashboard
sudo wget -q -O /var/lib/grafana/dashboards/system_metrics.json \
https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/grafana/system_metrics_dashboard.json

sudo chown -R grafana:grafana /var/lib/grafana

if ! curl -fsS "http://admin:$GRAFANA_PASSWORD@localhost:3000/api/user" > /dev/null; then
sudo curl -fsS -X PUT \
    -H "Content-Type: application/json" \
    -d "{\"oldPassword\":\"admin\",\"newPassword\":\"$GRAFANA_PASSWORD\",\"confirmNew\":\"$GRAFANA_PASSWORD\"}" \
    http://admin:admin@localhost:3000/api/user/password > /dev/null
fi

sudo systemctl restart grafana-server
until curl -fsS http://localhost:3000/api/health > /dev/null; do sleep 3; done

#--------------------------------------------------------------------------------------------------
if [ "$GRAFANA_ONLY_TEST" != "1" ]; then
log "openHAB user"

if ! sudo openhab-cli console -p habopen "user list" 2>/dev/null | grep -q "$OPENHAB_ADMIN_USER_NAME"; then
  sudo openhab-cli console -p habopen "user add $OPENHAB_ADMIN_USER_NAME $OPENHAB_ADMIN_USER_PASSWORD administrator"
fi
fi

#--------------------------------------------------------------------------------------------------
log "DONE"

echo "openHAB: http://<ip>:8080"
echo "Grafana: http://<ip>:3000"
