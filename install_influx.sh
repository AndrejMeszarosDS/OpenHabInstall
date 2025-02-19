# Variables
INFLUXDB_USER="orangepi"
INFLUXDB_PASSWORD="orangepi"
OPENHAB_USER="openhab"
OPENHAB_PASSWORD="openhab_password"
INFLUX_BUCKET="openhab_db"
INFLUX_ORG="openhab_db"
INFLUX_RETENTION="0" # Infinite retention

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
./influx setup --username "$INFLUX_USER" \
             --password "$INFLUXDB_PASSWORD" \
             --org "$INFLUXDB_ORG" \
             --bucket "$INFLUXDB_BUCKET" \
             --retention "$INFLUXDB_RETENTION" \
             --force




# OpenHAB Configuration File Path
OPENHAB_INFLUX_CFG="/etc/influxdb.cfg"

check_influx_cli() {
    if ! sudo orangepi/influx version; then
        echo "Influx CLI is not installed, not executable, or not in the correct directory."
        echo "Please verify that you have the correct InfluxDB CLI binary."
        exit 1
    fi
}

create_influx_token() {
    echo "Creating an authentication token for InfluxDB..."
    # Run the command with sudo and capture the token
    INFLUX_TOKEN=$(sudo orangepi/influx auth create \
        --org "$INFLUX_ORG" \
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
url=http://localhost:8086
token=$INFLUX_TOKEN
org=$INFLUX_ORG
bucket=$INFLUX_BUCKET
EOL

    echo "OpenHAB is now configured with InfluxDB token."
}


check_influx_cli
create_influx_token
configure_openhab
