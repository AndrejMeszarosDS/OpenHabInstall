#--------------------------------------------------------------------------------------------------
# update & upgrade                                                                                |
#--------------------------------------------------------------------------------------------------
#sudo apt-get update
#sudo apt-get -o Dpkg::Options::="--force-confnew" --force-yes -fuy dist-upgrade

#--------------------------------------------------------------------------------------------------
# install java 17                                                                                 |
#--------------------------------------------------------------------------------------------------
sudo apt install --yes --force-yes openjdk-17-jre-headless

#--------------------------------------------------------------------------------------------------
# install openHAB 4.1.3.1                                                                         |
#--------------------------------------------------------------------------------------------------
opanhab_admin_user_name = admin
opanhab_admin_user_password = openhab_password
curl -fsSL "https://openhab.jfrog.io/artifactory/api/gpg/key/public" | gpg --dearmor > openhab.gpg
sudo mkdir /usr/share/keyrings
sudo mv openhab.gpg /usr/share/keyrings
sudo chmod u=rw,g=r,o=r /usr/share/keyrings/openhab.gpg
echo 'deb [signed-by=/usr/share/keyrings/openhab.gpg] https://openhab.jfrog.io/artifactory/openhab-linuxpkg stable main' | sudo tee /etc/apt/sources.list.d/openhab.list
sudo apt install --yes --force-yes openhab=4.1.3-1
sudo apt-mark hold openhab
sudo apt-mark hold openhab-addons
sudo systemctl start openhab.service
sudo systemctl status openhab.service
sudo systemctl daemon-reload
sudo systemctl enable openhab.service
openhab-cli console -p habopen users add $opanhab_admin_user_name $opanhab_admin_user_password administrator
# update addons.cfg ( mqtt-binding, persistence mapdb, influx )

#--------------------------------------------------------------------------------------------------
# update & upgrade                                                                                |
#--------------------------------------------------------------------------------------------------
#sudo apt-get update
#sudo apt-get -o Dpkg::Options::="--force-confnew" --force-yes -fuy dist-upgrade

#--------------------------------------------------------------------------------------------------
# install frontail and dependecies and make to work                                               |
#--------------------------------------------------------------------------------------------------
# sudo apt-get install --yes --force-yes nodejs                            
# sudo apt-get install --yes --force-yes npm                               
# sudo npm i frontail -g --yes --force-yes
# cd ~/../../usr/local/lib/node_modules/frontail/web
# sudo rm index.html
# sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/frontail/index.html
# cd ~/../../usr/local/lib/node_modules/frontail/web/assets
# sudo rm app.js
# sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/frontail/app.js
# cd ~/../../usr/local/lib/node_modules/frontail/web/assets/styles
# sudo rm bootstrap.min.css
# sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/frontail/bootstrap.min.css
# cd ~/../../usr/local/lib/node_modules/frontail/preset
# sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/frontail/openhab_AEM.json
# cd ~/../../usr/local/lib/node_modules/frontail/web/assets/styles
# sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/frontail/openhab_AEM.css
# cd ~/../../etc/systemd/system
# sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/frontail/frontail.service
# sudo chmod 644 /etc/systemd/system/frontail.service
# sudo systemctl -q daemon-reload
# sudo systemctl enable --now frontail.service
# sudo systemctl restart frontail.service

#--------------------------------------------------------------------------------------------------
# update & upgrade                                                                                |
#--------------------------------------------------------------------------------------------------
#sudo apt-get update
#sudo apt-get -o Dpkg::Options::="--force-confnew" --force-yes -fuy dist-upgrade

#--------------------------------------------------------------------------------------------------
# samba share                                                                                     |
#--------------------------------------------------------------------------------------------------
# samba_share_password = secret
# sudo apt-get install --yes --force-yes samba samba-common-bin
# cd ~/../../etc/samba/
# sudo rm smb.conf
# sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/samba/smb.conf
# (echo "$samba_share_password"; echo "$samba_share_password") | smbpasswd -s -a "$SUDO_USER"
# sudo usermod -a -G openhab orangepi
# sudo chmod -R g+w /etc/openhab
# sudo systemctl restart smbd.service

#--------------------------------------------------------------------------------------------------
#install Mosquitto Broker                                                                         |
#--------------------------------------------------------------------------------------------------
# mosquitto_password = mqttpass
# sudo apt-get install -y mosquitto mosquitto-clients
# cd ~/../../etc/mosquitto/
# sudo rm mosquitto.conf
# sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/mosquitto/mosquitto.conf
# sudo mosquitto_passwd -b -c /etc/mosquitto/passwd orangepi $mosquitto_password
# sudo systemctl enable mosquitto.service
# sudo systemctl restart mosquitto
# add openhab MQTT addon



# ToDo
# install influx
# setup influx
# add opnhab influx addon
# set up openhab influx addon

# add test item and thinks

# check all together




