#!/usr/bin/env bash
set -euo pipefail

log() { echo -e "\n🔹 $1"; }

SCRIPT_USER="${SUDO_USER:-orangepi}"
HOME_DIR="/home/$SCRIPT_USER"

MOSQUITTO_PASSWORD="mqttpass"
SAMBA_SHARE_PASSWORD="secret"
OPENHAB_ADMIN_USER_NAME="admin"
OPENHAB_ADMIN_USER_PASSWORD="openhab_password"
INFLUXDB_USER="orangepi"
INFLUXDB_PASSWORD="orangepi"
INFLUXDB_ORG="openhab"
INFLUXDB_BUCKET="openhab"
INFLUXDB_RETENTION="0"
GRAFANA_PASSWORD="GrafanaPass_2026!"

install_if_missing() {
    dpkg -s "$1" >/dev/null 2>&1 || sudo apt-get install -y "$1"
}

#--------------------------------------------------------------------------------------------------
log "Update system"
sudo apt-get update
# sudo apt-get -y upgrade
# ask somwthing 

#-------------------------------------------------------------------------------------------------- X
log "Mosquitto"
# install_if_missing mosquitto
# install_if_missing mosquitto-clients

# sudo wget -q -O /etc/mosquitto/mosquitto.conf \
# https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/mosquitto/mosquitto.conf

# if [ ! -f /etc/mosquitto/passwd ]; then
#     sudo mosquitto_passwd -b -c /etc/mosquitto/passwd orangepi "$MOSQUITTO_PASSWORD"
# fi

# sudo systemctl enable --now mosquitto

#-------------------------------------------------------------------------------------------------- ok
log "Java"
install_if_missing openjdk-21-jre-headless

#-------------------------------------------------------------------------------------------------- ok
log "OpenHAB"
# sudo install -d -m 0755 /usr/share/keyrings
# curl -fsSL "https://openhab.jfrog.io/artifactory/api/gpg/key/public" | gpg --dearmor | sudo tee "$OPENHAB_KEYRING" > /dev/null
# sudo chmod 0644 "$OPENHAB_KEYRING"
# echo "deb [signed-by=$OPENHAB_KEYRING] https://openhab.jfrog.io/artifactory/openhab-linuxpkg stable main" | sudo tee "$OPENHAB_LIST_FILE" > /dev/null
# sudo apt-get update
# sudo apt install --yes --force-yes openhab=5.0.0-1
# sudo apt-mark hold openhab
# sudo apt-mark hold openhab-addons
# sudo systemctl daemon-reload
# sudo systemctl enable --now openhab.service

# if ! sudo systemctl list-unit-files | grep -q '^openhab.service'; then
#     echo "openHAB service was not installed correctly."
#     exit 1
# fi

# sudo systemctl status openhab.service --no-pager

#-------------------------------------------------------------------------------------------------- ok
log "Installing InfluxDB"
cd ~
curl -LO https://download.influxdata.com/influxdb/releases/influxdb2_2.7.7-1_arm64.deb
sudo dpkg -i influxdb2_2.7.7-1_arm64.deb
sudo service influxdb start

#--------------------------------------------------------------------------------------------------
log "Installing InfluxDB CLI"
cd ~
wget https://download.influxdata.com/influxdb/releases/influxdb2-client-2.7.5-linux-arm64.tar.gz
tar xvzf ./influxdb2-client-2.7.5-linux-arm64.tar.gz

#-------------------------------------------------------------------------------------------------- ok
log "Frontail"
if ! command -v node >/dev/null; then
    sudo apt-get install -y nodejs npm
fi

if ! npm list -g frontail >/dev/null 2>&1; then
    sudo npm install -g frontail
fi

BASE="/usr/local/lib/node_modules/frontail"

sudo wget -q -O $BASE/web/index.html https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/frontail/index.html
sudo wget -q -O $BASE/web/assets/app.js https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/frontail/app.js
sudo wget -q -O $BASE/web/assets/styles/bootstrap.min.css https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/frontail/bootstrap.min.css
sudo wget -q -O $BASE/web/assets/styles/openhab_AEM.css https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/frontail/openhab_AEM.css
sudo wget -q -O $BASE/preset/openhab_AEM.json https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/frontail/openhab_AEM.json

sudo wget -q -O /etc/systemd/system/frontail.service \
https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/frontail/frontail.service

sudo systemctl daemon-reload
sudo systemctl enable --now frontail

#-------------------------------------------------------------------------------------------------- ok
log "Samba"
sudo apt-get install --yes --force-yes samba samba-common-bin
cd ~/../../etc/samba/
sudo rm smb.conf
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/samba/smb.conf
(echo "$SAMBA_SHARE_PASSWORD"; echo "$SAMBA_SHARE_PASSWORD") | smbpasswd -s -a "$SCRIPT_USER"
sudo usermod -a -G openhab orangepi
sudo chmod -R g+w /etc/openhab
sudo chmod -R g+w /var/lib/openhab/jsondb
sudo systemctl restart smbd.service

#--------------------------------------------------------------------------------------------------
log "Creating InfluxDB admin user and database"

echo "Setting up InfluxDB admin user..."
./influx setup --username "$INFLUXDB_USER" \
             --password "$INFLUXDB_PASSWORD" \
             --org "$INFLUXDB_ORG" \
             --bucket "$INFLUXDB_BUCKET" \
             --retention "$INFLUXDB_RETENTION" \
             --force

# OpenHAB Configuration File Path
OPENHAB_INFLUX_CFG="/etc/openhab/services/influxdb.cfg"

#--------------------------------------------------------------------------------------------------
log "Checking InfluxDB CLI"
if ! sudo /root/influx version; then
    echo "Influx CLI is not installed, not executable, or not in the correct directory."
    echo "Please verify that you have the correct InfluxDB CLI binary."
    exit 1
fi

#--------------------------------------------------------------------------------------------------
log "Creating InfluxDB token"
echo "Creating an authentication token for InfluxDB..."
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
log "Configuring OpenHAB to use InfluxDB"
if [ ! -f "$OPENHAB_INFLUX_CFG" ]; then
    echo "InfluxDB configuration file not found, creating one..."
    sudo touch "$OPENHAB_INFLUX_CFG"
fi

# Backup old config
sudo cp "$OPENHAB_INFLUX_CFG" "$OPENHAB_INFLUX_CFG.bak"

# Write new config
sudo tee "$OPENHAB_INFLUX_CFG" > /dev/null <<EOL
# OpenHAB InfluxDB Configuration
version=V2
url=http://localhost:8086
token=$INFLUX_TOKEN
org=$INFLUXDB_ORG
bucket=$INFLUXDB_BUCKET
retentionPolicy=$INFLUXDB_BUCKET
EOL

echo "OpenHAB is now configured with InfluxDB token."

#--------------------------------------------------------------------------------------------------
log "Installing python dependencies for system metrics"
HOME_DIR="$SCRIPT_HOME"
VENV_DIR="$HOME_DIR/venv"
SYSTEM_METRICS_SCRIPT="$HOME_DIR/system_metrics.py"
INFLUX_URL="http://localhost:8086"

# Install Python, venv, pip, and dependencies
sudo apt-get update
sudo apt-get install -y python3 python3-venv python3-pip

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi

# Activate venv and install required Python packages
. "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install influxdb-client psutil
deactivate

# create system metrics script
cat << EOF > "$SYSTEM_METRICS_SCRIPT"
#!/usr/bin/env python3
import psutil, time
from influxdb_client import InfluxDBClient, Point, WriteOptions

# InfluxDB 2.x connection details
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
    # overall CPU usage
    record["cpu_percent"] = psutil.cpu_percent(interval=1)

    # per-core CPU usage (list of percentages)
    per_core = psutil.cpu_percent(interval=None, percpu=True)
    for i, usage in enumerate(per_core):
        record[f"cpu_core{i}_percent"] = usage

    # memory
    mem = psutil.virtual_memory()
    record["mem_total_mb"] = mem.total / 1024 / 1024
    record["mem_used_mb"] = mem.used / 1024 / 1024
    record["mem_percent"] = mem.percent

    # load averages
    record["load1"], record["load5"], record["load15"] = psutil.getloadavg()

    # temperatures
    record["cpu_temp"] = read_temp("/sys/class/thermal/thermal_zone0/temp")
    record["ddr_temp"] = read_temp("/sys/class/thermal/thermal_zone1/temp")
    record["gpu_temp"] = read_temp("/sys/class/thermal/thermal_zone2/temp")
    record["ve_temp"]  = read_temp("/sys/class/thermal/thermal_zone3/temp")

    return record

if __name__ == "__main__":
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

chmod +x "$SYSTEM_METRICS_SCRIPT"

# Create systemd service
SERVICE_FILE="/etc/systemd/system/system-metrics.service"

sudo tee "$SERVICE_FILE" > /dev/null <<EOL
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

# Enable and start systemd service
sudo systemctl daemon-reload
sudo systemctl enable system-metrics.service
sudo systemctl restart system-metrics.service
sudo systemctl status system-metrics.service

echo "System metrics service installed and running."