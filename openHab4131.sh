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
curl -LO https://download.influxdata.com/influxdb/releases/influxdb2_2.7.7-1_arm64.deb
sudo dpkg -i influxdb2_2.7.7-1_arm64.deb
sudo service influxdb start
#sudo service influxdb status ???

#--------------------------------------------------------------------------------------------------
# install influx CLI                                                                              |
#--------------------------------------------------------------------------------------------------
wget https://download.influxdata.com/influxdb/releases/influxdb2-client-2.7.5-linux-arm64.tar.gz
tar xvzf ./influxdb2-client-2.7.5-linux-arm64.tar.gz

#--------------------------------------------------------------------------------------------------
# create influx admin user and database                                                           |
#--------------------------------------------------------------------------------------------------
./influx setup \
  --username orangepi \
  --password orangepi_password \
  --org openhab \
  --bucket openhab_db \
  --force 
  

#--------------------------------------------------------------------------------------------------
# copy backup data from reposity to openhab                                                       |
#--------------------------------------------------------------------------------------------------
# items > /etc/openhab
cd ~/../../etc/openhab/items/
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/backup/irrigation.items
# things > /etc/openhab
cd ~/../../etc/openhab/things/
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/backup/irrigation.things
# rules > /etc/openhab
cd ~/../../etc/openhab/rules/
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/backup/irrigation.rules
# pagers & widgets > /etc/openhab
cd /var/lib/openhab/jsondb/
sudo rm uicomponents_ui_page.json
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/backup/uicomponents_ui_page.json
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/backup/uicomponents_ui_widget.json
#sudo systemctl restart openhab.service

#--------------------------------------------------------------------------------------------------
# copy addons config file                                                                         |
#--------------------------------------------------------------------------------------------------
cd ~/../../etc/openhab/services
sudo rm addons.cfg
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/openhab/addons.cfg
sudo systemctl restart openhab.service






#--------------------------------------------------------------------------------------------------
# influx setup finish setup                                                                       |
#--------------------------------------------------------------------------------------------------
# can access influx from browser
# http://192.168.0.145:8086/ influx_admin influx_admin_password
# we have influx config file
# check if we have persistence/influxdb.persist file ? no
# let create it
# trying correct persist file
# alse need set influx as default persist service but after restart it works without default persistence setup
# in openhab i edited the influx addon with ui, check the config file
# ok, the influxdb.cfg was not copied to openhab, this is still missing so we need to add to install script and try it pout
# cannot edit file influxdb.cfg permission
#  cd ~/../../etc/openhab/services
#  sudo chown orangepi:orangepi /etc/openhab/services/influxdb.cfg
# this helps
# but still influx needs token try to set it off


# ToDo
# finich influx setting and check




#  try to find, where is influxdb cli installed
# find / -type d -name "influxdb" 2>/dev/null
# check influx cli becouse manual reinstall solved to start it
# try to create user openhab openhab_password





# ./influx config create -a --username-password ADMINUSER -n myconfig -u http://127.0.0.1:8086
# ./influx user create –org openhab –-name openhab –-password openhab_password

# ./influx user create \
#   --name openhab \
#   --password openhab_password


#   ./influx config create \
#   -n test_config \
#   -u http://localhost:8086 \
#   -p influx_admin:influx_admin_password \
#   -o openhab



#   ./influx setup \
#   --username orangepi \
#   --password influx_admin_password \
#   --org openhab \
#   --bucket openhab_db \
#   --force 