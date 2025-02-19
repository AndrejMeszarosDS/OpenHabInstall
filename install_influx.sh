# Variables
INFLUXDB_USER="orangepi"
INFLUXDB_PASSWORD="orangepi"
#OPENHAB_USER="openhab"
#OPENHAB_PASSWORD="openhab_password"
INFLUXDB_BUCKET="openhab_db"
INFLUXDB_ORG="openhab_db"
INFLUXDB_RETENTION="0" # Infinite retention

#--------------------------------------------------------------------------------------------------
# update & upgrade                                                                                |
#--------------------------------------------------------------------------------------------------
sudo apt-get update
sudo apt-get -o Dpkg::Options::="--force-confnew" --force-yes -fuy dist-upgrade

#--------------------------------------------------------------------------------------------------
# install influx 1                                                                                |
#--------------------------------------------------------------------------------------------------

# Detect Raspberry Pi architecture
ARCH=$(uname -m)
INFLUXDB_VERSION="1.8.10"

echo "Detected architecture: $ARCH"

# Set download URL based on architecture
if [[ "$ARCH" == "armv7l" ]]; then
    URL="https://dl.influxdata.com/influxdb/releases/influxdb_${INFLUXDB_VERSION}_armhf.deb"
elif [[ "$ARCH" == "aarch64" ]]; then
    URL="https://dl.influxdata.com/influxdb/releases/influxdb_${INFLUXDB_VERSION}_arm64.deb"\else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

echo "Downloading InfluxDB v$INFLUXDB_VERSION from $URL"
wget -q --show-progress $URL -O influxdb.deb

# Install InfluxDB
echo "Installing InfluxDB..."
sudo dpkg -i influxdb.deb
sudo apt-get install -f -y

# Enable and start InfluxDB service
echo "Enabling and starting InfluxDB service..."
sudo systemctl enable influxdb
sudo systemctl start influxdb

# Clean up
echo "Cleaning up..."
rm influxdb.deb

echo "InfluxDB v$INFLUXDB_VERSION installation complete."
echo "Use 'systemctl status influxdb' to check the service status."












# curl -LO https://download.influxdata.com/influxdb/releases/influxdb2_2.7.7-1_arm64.deb
# sudo dpkg -i influxdb2_2.7.7-1_arm64.deb
# sudo service influxdb start

# wget https://download.influxdata.com/influxdb/releases/influxdb2-client-2.7.5-linux-arm64.tar.gz
# tar xvzf ./influxdb2-client-2.7.5-linux-arm64.tar.gz

# echo "Waiting for InfluxDB to start..."
# sleep 5

# echo "Setting up InfluxDB admin user..."
# ./influx setup --username "$INFLUXDB_USER" \
#              --password "$INFLUXDB_PASSWORD" \
#              --org "$INFLUXDB_ORG" \
#              --bucket "$INFLUXDB_BUCKET" \
#              --retention "$INFLUXDB_RETENTION" \
#              --force

#echo "Creating OpenHAB user..."
#sudo ./influx user create --name "$OPENHAB_USER" --password "$OPENHAB_PASSWORD"

#echo "Granting OpenHAB user read/write permissions on the bucket..."
#sudo ./influx auth create --user "$OPENHAB_USER" --write-buckets --read-buckets







#echo "Allowing password authentication..."
# printf "\n[http]\n  auth-enabled = true\n" | sudo tee -a /etc/influxdb/config.toml

#echo -e "\n[http]\n  auth-enabled = true" | sudo tee -a /etc/influxdb/config.toml
# sudo sudo tee /etc/influxdb/config.toml <<EOF >/dev/null
# [http]
#   auth-enabled = true
# EOF

#echo "Restarting InfluxDB service..."
#sudo systemctl restart influxdb
