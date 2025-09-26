#--------------------------------------------------------------------------------------------------
# update & upgrade                                                                                |
#--------------------------------------------------------------------------------------------------
sudo apt-get update
sudo apt-get -o Dpkg::Options::="--force-confnew" --force-yes -fuy dist-upgrade

#--------------------------------------------------------------------------------------------------
# install Mosquitto Broker                                                                        |
#--------------------------------------------------------------------------------------------------
mosquitto_password=mqttpass
sudo apt-get install -y mosquitto mosquitto-clients
cd ~/../../etc/mosquitto/
sudo rm mosquitto.conf
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/mosquitto/mosquitto.conf
sudo mosquitto_passwd -b -c /etc/mosquitto/passwd orangepi $mosquitto_password
sudo systemctl enable mosquitto.service
sudo systemctl restart mosquitto

#--------------------------------------------------------------------------------------------------
# install java 21                                                                                 |
#--------------------------------------------------------------------------------------------------
sudo apt install --yes --force-yes openjdk-21-jre-headless

#--------------------------------------------------------------------------------------------------
# install openHAB 5.0.0.1                                                          |
#--------------------------------------------------------------------------------------------------
curl -fsSL "https://openhab.jfrog.io/artifactory/api/gpg/key/public" | gpg --dearmor > openhab.gpg
sudo mkdir /usr/share/keyrings
sudo mv openhab.gpg /usr/share/keyrings
sudo chmod u=rw,g=r,o=r /usr/share/keyrings/openhab.gpg
echo 'deb [signed-by=/usr/share/keyrings/openhab.gpg] https://openhab.jfrog.io/artifactory/openhab-linuxpkg stable main' | sudo tee /etc/apt/sources.list.d/openhab.list
sudo apt-get update
sudo apt install --yes --force-yes openhab=5.0.0-1
sudo apt-mark hold openhab
sudo apt-mark hold openhab-addons
sudo systemctl start openhab.service
sudo systemctl status openhab.service
sudo systemctl daemon-reload
sudo systemctl enable openhab.service

#--------------------------------------------------------------------------------------------------
# install frontail and dependecies and make to work                                               |
#--------------------------------------------------------------------------------------------------
sudo apt-get install --yes --force-yes nodejs                            
sudo apt-get install --yes --force-yes npm                               
sudo npm i frontail -g --yes --force-yes
cd ~/../../usr/local/lib/node_modules/frontail/web
sudo rm index.html
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/frontail/index.html
cd ~/../../usr/local/lib/node_modules/frontail/web/assets
sudo rm app.js
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/frontail/app.js
cd ~/../../usr/local/lib/node_modules/frontail/web/assets/styles
sudo rm bootstrap.min.css
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/frontail/bootstrap.min.css
cd ~/../../usr/local/lib/node_modules/frontail/preset
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/frontail/openhab_AEM.json
cd ~/../../usr/local/lib/node_modules/frontail/web/assets/styles
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/frontail/openhab_AEM.css
cd ~/../../etc/systemd/system
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/frontail/frontail.service
sudo chmod 644 /etc/systemd/system/frontail.service
sudo systemctl -q daemon-reload
sudo systemctl enable --now frontail.service
sudo systemctl restart frontail.service

#--------------------------------------------------------------------------------------------------
# samba share                                                                                     |
#--------------------------------------------------------------------------------------------------
samba_share_password=secret
sudo apt-get install --yes --force-yes samba samba-common-bin
cd ~/../../etc/samba/
sudo rm smb.conf
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/samba/smb.conf
(echo "$samba_share_password"; echo "$samba_share_password") | smbpasswd -s -a "$SUDO_USER"
sudo usermod -a -G openhab orangepi
sudo chmod -R g+w /etc/openhab
sudo chmod -R g+w /var/lib/openhab/jsondb
sudo systemctl restart smbd.service

#--------------------------------------------------------------------------------------------------
# create openhab admin user                                                                       |
#--------------------------------------------------------------------------------------------------
opanhab_admin_user_name="admin"
opanhab_admin_user_password="openhab_password"
openhab-cli console -p habopen users add $opanhab_admin_user_name $opanhab_admin_user_password administrator

#--------------------------------------------------------------------------------------------------
# copy addons config file                                                                         |
#--------------------------------------------------------------------------------------------------
cd ~/../../etc/openhab/services
sudo rm addons.cfg
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/openhab/addons.cfg
sudo chown orangepi:orangepi ~/../../etc/openhab/services/addons.cfg

#--------------------------------------------------------------------------------------------------
# install influx                                                                                  |
#--------------------------------------------------------------------------------------------------
cd ~
curl -LO https://download.influxdata.com/influxdb/releases/influxdb2_2.7.7-1_arm64.deb
sudo dpkg -i influxdb2_2.7.7-1_arm64.deb
sudo service influxdb start

#--------------------------------------------------------------------------------------------------
# install influx CLI                                                                              |
#--------------------------------------------------------------------------------------------------
cd ~
wget https://download.influxdata.com/influxdb/releases/influxdb2-client-2.7.5-linux-arm64.tar.gz
tar xvzf ./influxdb2-client-2.7.5-linux-arm64.tar.gz

#--------------------------------------------------------------------------------------------------
# create influx admin user and database                                                           |
#--------------------------------------------------------------------------------------------------
INFLUXDB_USER="orangepi"
INFLUXDB_PASSWORD="orangepi"
OPENHAB_USER="openhab"
OPENHAB_PASSWORD="openhab_password"
INFLUXDB_BUCKET="openhab"
INFLUXDB_ORG="openhab"
INFLUXDB_RETENTION="0"

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
# check influx CLI                                                                                |
#--------------------------------------------------------------------------------------------------
if ! sudo /root/influx version; then
    echo "Influx CLI is not installed, not executable, or not in the correct directory."
    echo "Please verify that you have the correct InfluxDB CLI binary."
    exit 1
fi

#--------------------------------------------------------------------------------------------------
# create influx token                                                                             |
#--------------------------------------------------------------------------------------------------
echo "Creating an authentication token for InfluxDB..."
INFLUX_TOKEN=$(sudo /root/influx auth create \
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
# configure openhab to use influx                                                                 |
#--------------------------------------------------------------------------------------------------
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
# install python dependencies for system metrics                                                  |
#--------------------------------------------------------------------------------------------------
sudo apt-get install -y python3 python3-pip python3-psutil
pip3 install --user influxdb-client

#--------------------------------------------------------------------------------------------------
# create system metrics script                                                                    |
#--------------------------------------------------------------------------------------------------
HOME_DIR=$(eval echo ~orangepi)

cat << EOF > $HOME_DIR/system_metrics.py
#!/usr/bin/env python3
import psutil, time
from influxdb_client import InfluxDBClient, Point, WriteOptions

# InfluxDB 2.x connection details
url = "http://localhost:8086"
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
        metrics = collect_metrics()
        print(metrics)
        p = Point("system_metrics")
        for k,v in metrics.items():
            if v is not None:
                p = p.field(k, v)
        write_api.write(bucket=bucket, org=org, record=p)
        time.sleep(10)
EOF

chmod +x $HOME_DIR/system_metrics.py

#--------------------------------------------------------------------------------------------------
# set default persistence service                                                                 |
#--------------------------------------------------------------------------------------------------
sudo chown orangepi:orangepi /etc/openhab/services/runtime.cfg
if grep -q "org.openhab.persistence:default=" /etc/openhab/services/runtime.cfg; then
    sudo sed -i 's|org.openhab.persistence:default=.*|org.openhab.persistence:default=influxdb|' /etc/openhab/services/runtime.cfg
else
    printf "\norg.openhab.persistence:default=influxdb" | sudo tee -a /etc/openhab/services/runtime.cfg
fi

# restart openhab service
sudo systemctl restart openhab.service

#--------------------------------------------------------------------------------------------------
# create systemd service for system metrics                                                       |
#--------------------------------------------------------------------------------------------------
sudo tee /etc/systemd/system/system-metrics.service > /dev/null <<EOL
[Unit]
Description=OrangePi System Metrics Collector
After=network.target influxdb.service

[Service]
ExecStart=/usr/bin/python3 $HOME_DIR/system_metrics.py
WorkingDirectory=$HOME_DIR
Restart=always
RestartSec=10
User=orangepi
Environment="PYTHONUNBUFFERED=1"

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd, enable and start service
sudo systemctl daemon-reload
sudo systemctl enable system-metrics.service
sudo systemctl start system-metrics.service

#--------------------------------------------------------------------------------------------------
# install Grafana + configure InfluxDB data source + import system metrics dashboard               |
#--------------------------------------------------------------------------------------------------
GRAFANA_VERSION="9.6.2"
GRAFANA_USER="grafana"
GRAFANA_PASSWORD="grafana_password"   # Change to a secure password
GRAFANA_DEB="grafana_${GRAFANA_VERSION}_arm64.deb"

cd ~
wget https://dl.grafana.com/oss/release/$GRAFANA_DEB
sudo dpkg -i $GRAFANA_DEB

# start and enable Grafana service
sudo systemctl daemon-reload
sudo systemctl enable grafana-server.service
sudo systemctl start grafana-server.service

# set default admin user
sudo grafana-cli admin reset-admin-password $GRAFANA_PASSWORD
echo "Grafana installed and running at http://<orangepi-ip>:3000"

# configure InfluxDB data source for Grafana
GRAFANA_PROVISIONING_DIR="/etc/grafana/provisioning"
INFLUXDB_TOKEN="$INFLUX_TOKEN"  # From your previous install steps
INFLUXDB_ORG="openhab"
INFLUXDB_BUCKET="openhab"
INFLUXDB_URL="http://localhost:8086"

# create directories for provisioning
sudo mkdir -p $GRAFANA_PROVISIONING_DIR/datasources
sudo mkdir -p $GRAFANA_PROVISIONING_DIR/dashboards
sudo mkdir -p /var/lib/grafana/dashboards

# create InfluxDB datasource provisioning file
sudo tee $GRAFANA_PROVISIONING_DIR/datasources/influxdb.yaml > /dev/null <<EOL
apiVersion: 1
datasources:
  - name: InfluxDB
    type: influxdb
    access: proxy
    url: $INFLUXDB_URL
    database: $INFLUXDB_BUCKET
    user: $INFLUXDB_USER
    jsonData:
      version: Flux
      organization: $INFLUXDB_ORG
      defaultBucket: $INFLUXDB_BUCKET
    secureJsonData:
      token: $INFLUXDB_TOKEN
    isDefault: true
EOL

# create dashboard provisioning file
sudo tee $GRAFANA_PROVISIONING_DIR/dashboards/system_metrics.yaml > /dev/null <<EOL
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

# download system metrics dashboard JSON
sudo wget -O /var/lib/grafana/dashboards/system_metrics.json \
  https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/grafana/system_metrics_dashboard.json

sudo chown -R grafana:grafana /var/lib/grafana/dashboards
sudo systemctl restart grafana-server.service

echo "Grafana is fully configured with InfluxDB data source and system metrics dashboard."

#--------------------------------------------------------------------------------------------------
# copy backup data from reposity to openhab                                                       |
#--------------------------------------------------------------------------------------------------

# icons > /etc/openhab
cd /etc/openhab/icons/classic/ || exit 1
sudo wget -i /path/to/icons.txt
sudo chown orangepi:orangepi /etc/openhab/icons/classic/*.png

# items > /etc/openhab
cd /etc/openhab/items/ || exit 1
sudo wget -i /path/to/items.txt
sudo chown orangepi:orangepi /etc/openhab/items/*.items

# ui > /var/lib/openhab/jsondb
cd /var/lib/openhab/jsondb/ || exit 1
sudo wget -i /path/to/json.txt
sudo chown orangepi:orangepi /var/lib/openhab/jsondb/*.json

# persistence > /etc/openhab
cd /etc/openhab/persistence/ || exit 1
sudo wget -i /path/to/persist.txt
sudo chown orangepi:orangepi /etc/openhab/persistence/*.persist

# rules > /etc/openhab
cd /etc/openhab/rules/ || exit 1
sudo wget -i /path/to/rules.txt
sudo chown orangepi:orangepi /etc/openhab/rules/*.rules

# things > /etc/openhab
cd /etc/openhab/things/ || exit 1
sudo wget -i /path/to/things.txt
sudo chown orangepi:orangepi /etc/openhab/things/*.things

sudo systemctl restart openhab.service



# icons > /etc/openhab
#cd ~/../../etc/openhab/icons/classic/
#sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/backup/data/*.png
#sudo chown orangepi:orangepi /etc/openhab/items/irrigation.items
# # items > /etc/openhab
# cd ~/../../etc/openhab/items/
# sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/backup/data/irrigation.items
# sudo chown orangepi:orangepi /etc/openhab/items/irrigation.items
# # things > /etc/openhab
# cd ~/../../etc/openhab/things/
# sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/backup/data/irrigation.things
# sudo chown orangepi:orangepi /etc/openhab/things/irrigation.things
# # rules > /etc/openhab
# cd ~/../../etc/openhab/rules/
# sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/backup/data/irrigation.rules
# sudo chown orangepi:orangepi /etc/openhab/rules/irrigation.rules
# # persistence > /etc/openhab
# cd ~/../../etc/openhab/persistence/
# sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/backup/data/influxdb.persist
# sudo chown orangepi:orangepi /etc/openhab/persistence/influxdb.persist
# # pagers & widgets > /etc/openhab
# cd /var/lib/openhab/jsondb/
# sudo rm uicomponents_ui_page.json
# sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/backup/data/uicomponents_ui_page.json
# sudo chown openhab /var/lib/openhab/jsondb/uicomponents_ui_page.json
# sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/backup/data/uicomponents_ui_widget.json
# sudo chown openhab /var/lib/openhab/jsondb/uicomponents_ui_widget.json
# #sudo systemctl restart openhab.service





















# sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/openHab501.sh && sudo chmod 755 openHab501.sh && sudo ./openHab501.sh