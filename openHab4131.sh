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
# install java 17                                                                                 |
#--------------------------------------------------------------------------------------------------
sudo apt install --yes --force-yes openjdk-17-jre-headless

#--------------------------------------------------------------------------------------------------
# install openHAB 4.1.3.1                                                                         |
#--------------------------------------------------------------------------------------------------
curl -fsSL "https://openhab.jfrog.io/artifactory/api/gpg/key/public" | gpg --dearmor > openhab.gpg
sudo mkdir /usr/share/keyrings
sudo mv openhab.gpg /usr/share/keyrings
sudo chmod u=rw,g=r,o=r /usr/share/keyrings/openhab.gpg
echo 'deb [signed-by=/usr/share/keyrings/openhab.gpg] https://openhab.jfrog.io/artifactory/openhab-linuxpkg stable main' | sudo tee /etc/apt/sources.list.d/openhab.list
sudo apt-get update
sudo apt install --yes --force-yes openhab=4.1.3-1
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
# install influx                                                                                  |
#--------------------------------------------------------------------------------------------------
cd ~
curl -LO https://download.influxdata.com/influxdb/releases/influxdb2_2.7.7-1_arm64.deb
sudo dpkg -i influxdb2_2.7.7-1_arm64.deb
sudo service influxdb start
#sudo service influxdb status ???

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
INFLUXDB_BUCKET="openhab_db"
INFLUXDB_ORG="openhab_db"
INFLUXDB_RETENTION="0"

echo "Setting up InfluxDB admin user..."
./influx setup --username "$INFLUXDB_USER" \
             --password "$INFLUXDB_PASSWORD" \
             --org "$INFLUXDB_ORG" \
             --bucket "$INFLUXDB_BUCKET" \
             --retention "$INFLUXDB_RETENTION" \
             --force

echo "Creating OpenHAB user..."
./influx user create --name "$OPENHAB_USER" --password "$OPENHAB_PASSWORD"

echo "Granting OpenHAB user read/write permissions on the bucket..."
./influx auth create --user "$OPENHAB_USER" --write-buckets --read-buckets

echo "Allowing password authentication..."
sudo tee /etc/influxdb/config.toml <<EOF >/dev/null
[http]
  auth-enabled = true
EOF

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
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/backup/data/uicomponents_ui_widget.json
#sudo systemctl restart openhab.service

#--------------------------------------------------------------------------------------------------
# copy addons config file                                                                         |
#--------------------------------------------------------------------------------------------------
sudo systemctl stop openhab.service
sudo service influxdb stop
cd ~/../../etc/openhab/services
sudo rm addons.cfg
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/openhab/addons.cfg
sudo chown orangepi:orangepi ~/../../etc/openhab/services/addons.cfg
sudo rm influxdb.cfg
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/influxdb/influxdb.cfg
sudo chown orangepi:orangepi ~/../../etc/openhab/services/influxdb.cfg
sudo service influxdb start
sudo systemctl start openhab.service

#--------------------------------------------------------------------------------------------------
# influx setup finish setup                                                                       |
#--------------------------------------------------------------------------------------------------

# sudo shutdown -r now  > restart
# sudo poweroff         > pwer off
# add mapdb and influx persist cfg
# add influcdb.cfg
# modify restore to download all items, things .. files

# Openhab login : admin openhab_password
# host          : orangepizaero3
# mqtt          : orangepi mqttpass

# items 
# rules
# persist
# things
# addon.cfg
# influxdb.cfg

# sudo systemctl status influxdb.service
# sudo service influxdb stop
# sudo service influxdb start
# sudo systemctl restart openhab.service
# sudo service influxdb stop
# sudo service influxdb start
# sudo systemctl status influxdb.service
# sudo systemctl status openhab.service




