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
INSTALL_DIR=/srv/minecraft_server_bedrock
USER=minecraft
GROUP=minecraft
UUID_URL=https://api.mojang.com/users/profiles/minecraft/$1

# Screen scrape the server jar location from the Minecraft server download page
SERVER_JAR_URL="curl -L https://minecraft.net/en-us/download/server/bedrock/ | grep -Eo \"(http|https)://[a-zA-Z0-9./?=_-]*\" | sort | uniq | grep bin-linux"

apt update
apt install -y software-properties-common jq
apt install -y unzip

# Create user and install folder+
printf "Create %s user...\\n" "$USER"
adduser --system --no-create-home --home $INSTALL_DIR $USER
addgroup --system $GROUP
mkdir -pv $INSTALL_DIR

# Download the server jar
printf "Download %s/server.zip...\\n" "$INSTALL_DIR"
wget -q "$(eval "$SERVER_JAR_URL")" -O $INSTALL_DIR/server.zip
unzip $INSTALL_DIR/server.zip -d $INSTALL_DIR/

# Set permissions on install folder
chown -R $USER $INSTALL_DIR

# Create a service
printf "Create service..."
cat <<EOF | tee /etc/systemd/system/minecraft-server-bedrock.service
[Unit]
Description=Minecraft Bedrock Server
After=rc-local.service

[Service]
WorkingDirectory=$INSTALL_DIR
User=$USER
ProtectSystem=full
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ExecStart=/bin/bash -c 'LD_LIBRARY_PATH=. ./bedrock_server'
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
Alias=minecraft-server-bedrock.service
EOF
printf "Service create to launch\\n"

# Configure the server
printf "Configure the server..."
echo 'eula=true' | tee $INSTALL_DIR/eula.txt

mojang_output="$(wget -qO- "$UUID_URL")"
rawUUID="$(echo "${mojang_output}" | jq -r '.id')"
UUID=${rawUUID:0:8}-${rawUUID:8:4}-${rawUUID:12:4}-${rawUUID:16:4}-${rawUUID:20:12}
cat <<EOF | tee $INSTALL_DIR/permissions.json
[
  {
    "xuid": "$UUID",
    "name": "$1",
    "permission": "operator"
  }
]
EOF
chown $USER:$GROUP $INSTALL_DIR/permissions.json

cat <<EOF | tee $INSTALL_DIR/server.properties
# https://minecraft.gamepedia.com/Server.properties#Bedrock_Edition_3
server-name=$3
gamemode=$4
difficulty=$2
allow-cheats=false
max-players=10
online-mode=true
white-list=$5
server-port=19132
server-portv6=19133
view-distance=32
tick-distance=4
player-idle-timeout=30
max-threads=0
level-name=$3
level-seed=$9
default-player-permission-level=visitor
texturepack-required=false
content-log-file-enabled=false
EOF
chown $USER:$GROUP $INSTALL_DIR/server.properties

systemctl daemon-reload
systemctl enable minecraft-server-bedrock && echo "Enable minecraft-server-bedrock..." || echo "minecraft-server-bedrock already enabled. Skipping..."
systemctl start minecraft-server-bedrock
