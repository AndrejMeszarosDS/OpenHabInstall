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
sudo chmod -R g+w /var/lib/openhab
sudo systemctl restart smbd.service

#--------------------------------------------------------------------------------------------------
# create openhab admin user                                                                       |
#--------------------------------------------------------------------------------------------------
opanhab_admin_user_name="admin"
opanhab_admin_user_password="openhab_password"
openhab-cli console -p habopen users add $opanhab_admin_user_name $opanhab_admin_user_password administrator

#--------------------------------------------------------------------------------------------------
# copy backup data from reposity to openhab                                                       |
#--------------------------------------------------------------------------------------------------
# items > /etc/openhab
cd ~/../../etc/openhab/items/
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/backup/data/irrigation.items
sudo chown orangepi:orangepi /etc/openhab/items/irrigation.items
# things > /etc/openhab
cd ~/../../etc/openhab/things/
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/backup/data/irrigation.things
sudo chown orangepi:orangepi /etc/openhab/things/irrigation.things
# rules > /etc/openhab
cd ~/../../etc/openhab/rules/
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/backup/data/irrigation.rules
sudo chown orangepi:orangepi /etc/openhab/rules/irrigation.rules
# persistence > /etc/openhab
cd ~/../../etc/openhab/persistence/
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/backup/data/influxdb.persist
sudo chown orangepi:orangepi /etc/openhab/persistence/influxdb.persist
# pagers & widgets > /etc/openhab
cd /var/lib/openhab/jsondb/
sudo rm uicomponents_ui_page.json
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/backup/data/uicomponents_ui_page.json
sudo chown openhab /var/lib/openhab/jsondb/uicomponents_ui_page.json
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/backup/data/uicomponents_ui_widget.json
sudo chown openhab /var/lib/openhab/jsondb/uicomponents_ui_widget.json
#sudo systemctl restart openhab.service

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

check_influx_cli() {
    if ! sudo /root/influx version; then
        echo "Influx CLI is not installed, not executable, or not in the correct directory."
        echo "Please verify that you have the correct InfluxDB CLI binary."
        exit 1
    fi
}

create_influx_token() {
    echo "Creating an authentication token for InfluxDB..."
    # Run the command with sudo and capture the token
    INFLUX_TOKEN=$(sudo /root/influx auth create \
        --org "$INFLUXDB_ORG" \
        --description "OpenHAB Token" \
        --all-access \
        --hide-headers | awk 'NR==1 {print $4}')

    # Check if the token was successfully created
    if [ -z "$INFLUX_TOKEN" || "$INFLUX_TOKEN" == "Error" ]; then
        echo "Failed to create InfluxDB token. Verify your InfluxDB setup and credentials."
        exit 1
    fi

    echo "Token successfully created: $INFLUX_TOKEN"
}

# Function to configure OpenHAB with the InfluxDB token
configure_openhab() {
    echo "Configuring OpenHAB to use InfluxDB token..."

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
}


check_influx_cli
create_influx_token
configure_openhab


# set default persis service
sudo chown orangepi:orangepi /etc/openhab/services/runtime.cfg
printf "\norg.openhab.persistence:default=influxdb" | sudo tee -a /etc/openhab/services/runtime.cfg

# restart openhab service
sudo systemctl restart openhab.service


# sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/openHab501.sh && sudo chmod 755 openHab501.sh && sudo ./openHab501.sh