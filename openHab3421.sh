# update & upgrade
sudo apt-get update
sudo apt-get -o Dpkg::Options::="--force-confnew" --force-yes -fuy dist-upgrade
# install java 17
sudo apt install --yes --force-yes openjdk-17-jre-headless
# install openHAB 3.4.2.1
curl -fsSL "https://openhab.jfrog.io/artifactory/api/gpg/key/public" | gpg --dearmor > openhab.gpg
sudo mkdir /usr/share/keyrings
sudo mv openhab.gpg /usr/share/keyrings
sudo chmod u=rw,g=r,o=r /usr/share/keyrings/openhab.gpg
echo 'deb [signed-by=/usr/share/keyrings/openhab.gpg] https://openhab.jfrog.io/artifactory/openhab-linuxpkg stable main' | sudo tee /etc/apt/sources.list.d/openhab.list
sudo apt-get --yes --force-yes update
sudo apt install --yes --force-yes openhab=3.4.2-1
sudo apt-mark hold openhab
sudo apt-mark hold openhab-addons
sudo systemctl start openhab.service
sudo systemctl status openhab.service
sudo systemctl daemon-reload
sudo systemctl enable openhab.service
openhab-cli info
# update & upgrade
sudo apt-get update
sudo apt-get -o Dpkg::Options::="--force-confnew" --force-yes -fuy dist-upgrade
# install frontail and dependecies
sudo apt-get install --yes --force-yes nodejs                            
sudo apt-get install --yes --force-yes npm                               
sudo npm i frontail -g --yes --force-yes
# remake frontail to work
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
# update & upgrade
sudo apt-get update
sudo apt-get -o Dpkg::Options::="--force-confnew" --force-yes -fuy dist-upgrade
# samba share
sudo apt-get install --yes --force-yes samba samba-common-bin
# samba load updated configuration
cd ~/../../etc/samba/
sudo rm smb.conf
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/samba/smb.conf
# set user and password orangepi/secret
pass="secret"
(echo "$pass"; echo "$pass") | smbpasswd -s -a "$SUDO_USER"
# restart samba service
sudo systemctl restart smbd.service