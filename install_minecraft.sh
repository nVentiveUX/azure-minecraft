#!/bin/bash
# Custom Minecraft server install script for Ubuntu
# $1 = Minecraft user name, to be an operator of the server.
# $2 = difficulty, 0 - Peaceful, 1 - Easy, 2 - Normal, 3 - Hard. See http://minecraft.gamepedia.com/Server.properties
# $3 = level-name, Name of your world. No spaces, single quotes, explanation marks, backslashes
# $4 = gamemode, 0 - Survival, 1 - Creative, 2 - Adventure, 3 - Spectator
# $5 = white-list, set this to true to make this invite-only. (Default: False)
# $6 = enable-command-block, if this is true you can create command blocks in the server. (Default: False)
# $7 = spawn-monsters, controls whether monsters show up at night or not. (Default: True)
# $8 = generate-structures, controls whether your world will have temples and villages. (Default: True)
# $9 = level-seed, Leave this blank to use a random seed.

set -eu -o pipefail

# Basic service and API settings
INSTALL_DIR=/srv/minecraft_server
USER=minecraft
GROUP=minecraft
UUID_URL=https://api.mojang.com/users/profiles/minecraft/$1

# Screen scrape the server jar location from the Minecraft server download page
SERVER_JAR_URL="curl -L https://minecraft.net/en-us/download/server/ | grep -Eo \"(http|https)://[a-zA-Z0-9./?=_-]*\" | sort | uniq | grep launcher"

apt update
apt install -y software-properties-common
apt install -y default-jdk

# Create user and install folder+
printf "Create $USER user...\\n"
adduser --system --no-create-home --home $INSTALL_DIR $USER
addgroup --system $GROUP
mkdir -pv $INSTALL_DIR

# Download the server jar
printf "Download $INSTALL_DIR/server.jar...\\n"
wget -q `eval $SERVER_JAR_URL` -O $INSTALL_DIR/server.jar

# Set permissions on install folder
chown -R $USER $INSTALL_DIR

# Adjust memory usage depending on VM size
totalMem=$(free -m | awk '/Mem:/ { print $2 }')
if [ $totalMem -lt 2048 ]; then
    memoryAllocs=512m
    memoryAllocx=1g
else
    memoryAllocs=1g
    memoryAllocx=2g
fi

# Create a service
printf "Create service..."
cat <<EOF | tee /etc/systemd/system/minecraft-server.service
[Unit]
Description=Minecraft Service
After=rc-local.service

[Service]
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/java -Xms$memoryAllocs -Xmx$memoryAllocx -jar $INSTALL_DIR/server.jar nogui
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
Alias=minecraft-server.service
EOF
printf "Service create to launch:"
printf "/usr/bin/java -Xms$memoryAllocs -Xmx$memoryAllocx -jar $INSTALL_DIR/server.jar nogui\\n"

# Configure the server
printf "Configure the server..."
echo 'eula=true' | tee $INSTALL_DIR/eula.txt

mojang_output="`wget -qO- $UUID_URL`"
rawUUID=${mojang_output:7:32}
UUID=${rawUUID:0:8}-${rawUUID:8:4}-${rawUUID:12:4}-${rawUUID:16:4}-${rawUUID:20:12}
cat <<EOF | tee $INSTALL_DIR/ops.json
[
  {
    "uuid": "$UUID",
    "name": "$1",
    "level": 4
  }
]
EOF
chown $USER:$GROUP $INSTALL_DIR/ops.json

cat <<EOF | tee $INSTALL_DIR/server.properties
difficulty=$2
level-name=$3
gamemode=$4
white-list=$5
enable-command-block=$6
spawn-monsters=$7
generate-structures=$8
level-seed=$9
motd=Welcome on $3
EOF
chown $USER:$GROUP $INSTALL_DIR/server.properties

systemctl daemon-reload
systemctl enable minecraft-server
systemctl start minecraft-server
