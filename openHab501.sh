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
install_if_missing mosquitto
install_if_missing mosquitto-clients

sudo wget -q -O /etc/mosquitto/mosquitto.conf \
https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/mosquitto/mosquitto.conf

if [ ! -f /etc/mosquitto/passwd ]; then
    sudo mosquitto_passwd -b -c /etc/mosquitto/passwd orangepi "$MOSQUITTO_PASSWORD"
fi

sudo systemctl enable --now mosquitto

#-------------------------------------------------------------------------------------------------- ok
log "Java"
install_if_missing openjdk-21-jre-headless

#-------------------------------------------------------------------------------------------------- ok
log "OpenHAB"
if ! dpkg -s openhab >/dev/null 2>&1; then
    sudo mkdir -p /usr/share/keyrings
    curl -fsSL https://openhab.jfrog.io/artifactory/api/gpg/key/public | \
        gpg --dearmor | sudo tee /usr/share/keyrings/openhab.gpg > /dev/null

    echo 'deb [signed-by=/usr/share/keyrings/openhab.gpg] https://openhab.jfrog.io/artifactory/openhab-linuxpkg stable main' | \
        sudo tee /etc/apt/sources.list.d/openhab.list

    sudo apt-get update
    sudo apt-get install -y openhab=5.0.0-1
    sudo apt-mark hold openhab openhab-addons
fi

sudo systemctl enable --now openhab

#-------------------------------------------------------------------------------------------------- ok
log "Waiting for OpenHAB to fully start..."

for i in {1..60}; do
    if sudo systemctl is-active --quiet openhab && \
       sudo -u openhab timeout 2 bash -c '</dev/tcp/127.0.0.1/8101' 2>/dev/null; then
        
        # check if console responds
        if echo "bundle:list" | sudo -u openhab nc localhost 8101 >/dev/null 2>&1; then
            echo "OpenHAB is ready"
            break
        fi
    fi

    echo "Still starting... ($i)"
    sleep 5
done

if ! sudo -u openhab openhab-cli console -p habopen "user:list" | grep -q "$OPENHAB_ADMIN_USER_NAME"; then
    echo "Creating OpenHAB admin user..."

    sudo -u openhab openhab-cli console -p habopen <<EOF
user:add $OPENHAB_ADMIN_USER_NAME $OPENHAB_ADMIN_USER_PASSWORD
user:roles:add $OPENHAB_ADMIN_USER_NAME administrator
logout
EOF
else
    echo "User already exists"
fi

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
install_if_missing samba

sudo wget -q -O /etc/samba/smb.conf \
https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/samba/smb.conf

(echo "$SAMBA_SHARE_PASSWORD"; echo "$SAMBA_SHARE_PASSWORD") | sudo smbpasswd -s -a "$SCRIPT_USER" || true

sudo usermod -a -G openhab "$SCRIPT_USER" || true
sudo chmod -R g+w /etc/openhab /var/lib/openhab/jsondb || true

sudo systemctl restart smbd

#-------------------------------------------------------------------------------------------------- ok