# Variables
INFLUXDB_USER="orangepi"
INFLUXDB_PASSWORD="orangepi"
OPENHAB_USER="openhab"
OPENHAB_PASSWORD="openhabpassword"
INFLUXDB_BUCKET="openhab_db"
INFLUXDB_ORG="openhab_org"
INFLUXDB_RETENTION="0" # Infinite retention

#--------------------------------------------------------------------------------------------------
# update & upgrade                                                                                |
#--------------------------------------------------------------------------------------------------
sudo apt-get update
sudo apt-get -o Dpkg::Options::="--force-confnew" --force-yes -fuy dist-upgrade


#--------------------------------------------------------------------------------------------------
# install influx                                                                                  |
#--------------------------------------------------------------------------------------------------
curl -LO https://download.influxdata.com/influxdb/releases/influxdb2_2.7.7-1_arm64.deb
sudo dpkg -i influxdb2_2.7.7-1_arm64.deb
sudo service influxdb start

wget https://download.influxdata.com/influxdb/releases/influxdb2-client-2.7.5-linux-arm64.tar.gz
tar xvzf ./influxdb2-client-2.7.5-linux-arm64.tar.gz

echo "Waiting for InfluxDB to start..."
sleep 5

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

echo "Restarting InfluxDB service..."
sudo systemctl restart influxdb
