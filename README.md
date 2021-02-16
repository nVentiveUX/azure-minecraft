# Minecraft server on Azure

Table of contents

  1. [About](#about)
  2. [Disclaimer](#disclaimer)
  3. [Known issue](#known-issue)
  4. [Usage](#usage)
  5. [Delete the Azure infrastructure](#delete-the-azure-infrastructure)

## About

This project automates the set-up process for a working Minecraft server hosted on Azure Standard B1ms.
The development of this project is heavily inspired by this [Azure template](hhttps://github.com/Azure/azure-quickstart-templates/tree/master/minecraft-on-ubuntu).

## Disclaimer

**This software comes with no warranty of any kind**. USE AT YOUR OWN RISK! This a personal project and is NOT endorsed by Microsoft. If you encounter an issue, please submit it on GitHub.

## Known issue

None.

## Usage

### Create the infrastructure in Azure

* The only requirement is to have AZ CLI installed. You can use the [Azure Cloud Shell](https://shell.azure.com/)
* Do not forget to update the options values of the below example.

```shell
(
rm -rf ~/azure-minecraft
git clone https://github.com/nVentiveUX/azure-minecraft.git
cd ~/azure-minecraft

# Yvesub example
./create_vm.sh \
    --subscription="8d8af6bf-9138-4d9d-a2e6-5bff1e3044c5" \
    --location="francecentral" \
    --rg-vnet="rg-shared-001" \
    --vnet-name="vnt-shared-001" \
    --subnet-name="snt-minecraft-001" \
    --subnet="10.1.0.32/29" \
    --rg-vm="rg-inf-minecraft-001" \
    --vm-name="vm-minecraft-001" \
    --lb-name="lb-minecraft-001" \
    --dns-name="lebonserv"
)
```

### Configure the Virtual Machine

* Connect using SSH on port 443
* Install Java edition

```shell
(
sudo apt update && sudo apt dist-upgrade -Vy &&
wget -O install_minecraft.sh "https://github.com/nVentiveUX/azure-minecraft/raw/master/install_minecraft_java.sh" &&
chmod +x install_minecraft.sh &&
sudo ./install_minecraft.sh "Felbarr" "2" "LeBonMonde" "0" "False" "True" "True" "True" "867832618049646" &&
tail -f /srv/minecraft_server_java/logs/latest.log
)
```

* Install Bedrock edition

```shell
(
sudo apt update && sudo apt dist-upgrade -Vy &&
wget -O install_minecraft.sh "https://github.com/nVentiveUX/azure-minecraft/raw/master/install_minecraft_bedrock.sh" &&
chmod +x install_minecraft.sh &&
sudo ./install_minecraft.sh "Felbarr90" "2" "LeBonMonde" "0" "False" "True" "True" "True" "33480944" &&
journalctl -exu minecraft-server-bedrock
)
```

### Set-up the backup system

```shell
(
STORAGE_ACCOUNT_NAME="stalebonservwesteurope"
STORAGE_SAS_TOKEN=""
STORAGE_ACCOUNT_CONTAINER="backup-001"

printf "Set-up \"/etc/cron.d/minecraft\" backup system...\\n"
sudo mkdir -p /usr/share/minecraft/maintenance
sudo wget -q "https://github.com/nVentiveUX/azure-minecraft/raw/master/azure_backup.sh" -O /usr/share/minecraft/maintenance/azure_backup.sh
sudo chmod +x /usr/share/minecraft/maintenance/azure_backup.sh
cat <<EOF | sudo tee /etc/cron.d/minecraft >/dev/null 2>&1
SHELL=/bin/bash
# m h dom mon dow user    command
# Backup
0 5 * * *  root  /usr/share/minecraft/maintenance/azure_backup.sh "$STORAGE_ACCOUNT_NAME" "$STORAGE_SAS_TOKEN" "$STORAGE_ACCOUNT_CONTAINER" >/dev/null 2>&1
EOF
)
```

### Play

Connect on ```lebonserv.westeurope.cloudapp.azure.com:25565```

The full list of operator commands can be found on the Minecraft wiki:  http://minecraft.gamepedia.com/Commands#Summary_of_commands

### Get the logs

```shell
journalctl -exu minecraft-server
journalctl -exu minecraft-server-bedrock
```

## Delete the Azure infrastructure

```shell
az group delete --name rg-inf-minecraft-001
```
