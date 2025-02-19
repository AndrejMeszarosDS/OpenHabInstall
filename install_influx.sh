# Variables
INFLUXDB_USER="orangepi"
INFLUXDB_PASSWORD="orangepi"
OPENHAB_USER="openhab"
OPENHAB_PASSWORD="openhab_password"
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


#!/bin/bash

# OpenHAB Configuration File Path
OPENHAB_INFLUX_CFG="/etc/openhab/services/influxdb.cfg"

# Function to check if Influx CLI is installed
check_influx_cli() {
    if ! command -v influx &> /dev/null; then
        echo "Influx CLI is not installed. Please install it first."
        exit 1
    fi
}

# Function to create InfluxDB authentication token
create_influx_token() {
    echo "Creating an authentication token for InfluxDB..."
    
    # Authenticate and generate token
    INFLUX_TOKEN=$(influx auth create \
        --user "$INFLUX_USER" \
        --org "$INFLUX_ORG" \
        --description "OpenHAB Token" \
        --read-bucket "$INFLUX_BUCKET" \
        --write-bucket "$INFLUX_BUCKET" \
        --hide-headers | awk '{print $3}')
    
    if [ -z "$INFLUX_TOKEN" ]; then
        echo "Failed to create InfluxDB token. Check your InfluxDB setup."
        exit 1
    fi

    echo "Token successfully created."
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
url=http://localhost:8086
token=$INFLUX_TOKEN
org=$INFLUX_ORG
bucket=$INFLUX_BUCKET
EOL

    echo "OpenHAB is now configured with InfluxDB token."
}

# Restart OpenHAB service
restart_openhab() {
    echo "Restarting OpenHAB to apply changes..."
    sudo systemctl restart openhab
    echo "OpenHAB restarted successfully."
}

# Run setup
check_influx_cli
create_influx_token
configure_openhab
restart_openhab

echo "InfluxDB authentication setup for OpenHAB is complete!"



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
