cd ~/../../etc/openhab/items 
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/test_data/influx.items
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/test_data/mapdb.items

cd ~/../../etc/openhab/things
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/test_data/influx.things

cd ~/../../etc/openhab/persistence
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/openhab/influxdb.persist
sudo wget https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/openhab/mapdb.persist

cd ~/../../etc/openhab/services
rm -f addons.cfg
sudo wget -c https://raw.githubusercontent.com/AndrejMeszarosDS/OpenHabInstall/main/openhab/addons.cfg
