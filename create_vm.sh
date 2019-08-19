#!/bin/bash

set -eu -o pipefail

PROGNAME="$(basename "$0")"

# Parse arguments
ARGS=$(getopt \
    --options s:l:g:v:s:n:r:m:b:d \
    --longoptions subscription:,location:,rg-vnet:,vnet-name:,subnet-name:,subnet:,rg-vm:,vm-name:,lb-name:,dns-name: \
    -n "${PROGNAME}" -- "$@")
eval set -- "${ARGS}"
unset ARGS

AZ_SUBSCRIPTION_ID=""
AZ_LOCATION=""
AZ_VNET_RG=""
AZ_VNET=""
AZ_VNET_SUBNET_NAME=""
AZ_VNET_SUBNET=""
AZ_VM_RG=""
AZ_VM=""
AZ_LB=""
AZ_LB_DNS=""

while true; do
  case "$1" in
    '-s'|'--subscription')
        AZ_SUBSCRIPTION_ID="$2"
        shift 2
        continue
    ;;
    '-l'|'--location')
        AZ_LOCATION="$2"
        shift 2
        continue
    ;;
    '-g'|'--rg-vnet')
        AZ_VNET_RG="$2"
        shift 2
        continue
    ;;
    '-v'|'--vnet-name')
        AZ_VNET="$2"
        shift 2
        continue
    ;;
    '-s'|'--subnet-name')
        AZ_VNET_SUBNET_NAME="$2"
        shift 2
        continue
    ;;
    '-n'|'--subnet')
        AZ_VNET_SUBNET="$2"
        shift 2
        continue
    ;;
    '-r'|'--rg-vm')
        AZ_VM_RG="$2"
        shift 2
        continue
    ;;
    '-m'|'--vm-name')
        AZ_VM="$2"
        shift 2
        continue
    ;;
    '-b'|'--lb-name')
        AZ_LB="$2"
        shift 2
        continue
    ;;
    '-d'|'--dns-name')
        AZ_LB_DNS="$2"
        shift 2
        continue
    ;;
    '--')
        shift
        break
    ;;
    *)
        usage
        exit 1
    ;;
  esac
done

# Show usage
usage() {
    printf "usage: %s --subscription=<name> --location=<name> --rg-vnet=<name> --vnet-name=<name> --subnet-name=<name> --subnet=<name> --rg-vm=<name> --vm-name=<name> --lb-name=<name> --dns-name=<name>\\n" "${PROGNAME}"
}

# Pre-checks
if [[ -z $AZ_SUBSCRIPTION_ID ]]; then
    echo "Error: --subscription is required !"
    usage
    exit 1
fi

if [[ -z $AZ_LOCATION ]]; then
    echo "Error: --location is required !"
    usage
    exit 1
fi

if [[ -z $AZ_VNET_RG ]]; then
    echo "Error: --rg-vnet is required !"
    usage
    exit 1
fi

if [[ -z $AZ_VNET ]]; then
    echo "Error: --vnet-name is required !"
    usage
    exit 1
fi

if [[ -z $AZ_VNET_SUBNET_NAME ]]; then
    echo "Error: --subnet-name is required !"
    usage
    exit 1
fi

if [[ -z $AZ_VNET_SUBNET ]]; then
    echo "Error: --subnet is required !"
    usage
    exit 1
fi

if [[ -z $AZ_VM_RG ]]; then
    echo "Error: --rg-vm is required !"
    usage
    exit 1
fi

if [[ -z $AZ_VM ]]; then
    echo "Error: --vm-name is required !"
    usage
    exit 1
fi

if [[ -z $AZ_LB ]]; then
    echo "Error: --lb-name is required !"
    usage
    exit 1
fi

if [[ -z $AZ_LB_DNS ]]; then
    echo "Error: --dns-name is required !"
    usage
    exit 1
fi

printf "Switch to ${AZ_SUBSCRIPTION_ID} subscription...\\n"
az account set --subscription "${AZ_SUBSCRIPTION_ID}" --output none

if ! az network vnet show --resource-group ${AZ_VNET_RG} --name ${AZ_VNET} --output none; then
    printf "Create ${AZ_VNET_RG} resource group...\\n"
    az group create \
        --location "${AZ_LOCATION}" \
        --name "${AZ_VNET_RG}"

    printf "Create a new 10.1.0.0/16 VNET named ${AZ_VNET}...\\n"
    az network vnet create \
        --resource-group "${AZ_VNET_RG}" \
        --name "${AZ_VNET}" \
        --address-prefix "10.1.0.0/16"
fi

printf "Create a new ${AZ_VNET_SUBNET} subnet named ${AZ_VNET_SUBNET_NAME}...\\n"
az network vnet subnet create \
    --resource-group "${AZ_VNET_RG}" \
    --vnet-name "${AZ_VNET}" \
    --name "${AZ_VNET_SUBNET_NAME}" \
    --address-prefix "${AZ_VNET_SUBNET}" \
    --output none

printf "Create ${AZ_VM_RG} resource group...\\n"
az group create \
    --location "${AZ_LOCATION}" \
    --name "${AZ_VM_RG}" \
    --output none

printf "Create sta${AZ_LB_DNS} Storage Account...\\n"
az storage account create \
    --resource-group "${AZ_VM_RG}" \
    --name "sta${AZ_LB_DNS}" \
    --location "${AZ_LOCATION}" \
    --https-only true \
    --kind StorageV2 \
    --encryption-services blob \
    --access-tier Cool \
    --sku Standard_LRS \
    --output none

printf "Create backup-001 blob container...\\n"
az storage container create \
    --name backup-001 \
    --account-name "sta${AZ_LB_DNS}" \
    --public-access off \
    --output none

printf "Create a ReadWrite policy for backup-001 blob container...\\n"
az storage container policy create \
    --container-name backup-001 \
    --account-name "sta${AZ_LB_DNS}" \
    --name rw \
    --permissions rw \
    --expiry `date -u -d "20 years" '+%Y-%m-%dT%H:%MZ'` \
    --start `date -u -d "-1 days" '+%Y-%m-%dT%H:%MZ'` \
    --output none

printf "Generate SAS Token to access the backup-001 blob container...\\n"
az storage container generate-sas \
    --name backup-001 \
    --account-name "sta${AZ_LB_DNS}" \
    --policy-name rw \
    --output none

printf "Create ${AZ_LB_DNS}.${AZ_LOCATION}.cloudapp.azure.com basic public IP address...\\n"
az network public-ip create \
    --name "${AZ_LB}-public-ip" \
    --resource-group "${AZ_VM_RG}" \
    --allocation-method "Dynamic" \
    --sku "Basic" \
    --version "IPv4" \
    --dns-name "${AZ_LB_DNS}" \
    --output none

printf "Create ${AZ_LB} basic load balancer...\\n"
az network lb create \
    --name "${AZ_LB}" \
    --resource-group "${AZ_VM_RG}" \
    --public-ip-address "${AZ_LB}-public-ip" \
    --frontend-ip-name "${AZ_LB}-public-ip" \
    --backend-pool-name "${AZ_VM}-backendpool" \
    --sku "Basic" \
    --output none

printf "Create NAT pool rules for SSH connection...\\n"
az network lb inbound-nat-rule create \
    --name "${AZ_VM}-ssh" \
    --resource-group "${AZ_VM_RG}" \
    --lb-name "${AZ_LB}" \
    --frontend-port "443" \
    --backend-port "22" \
    --frontend-ip-name "${AZ_LB}-public-ip" \
    --protocol "tcp" \
    --output none

printf "Create NAT pool rules for Minecraft connection...\\n"
az network lb inbound-nat-rule create \
    --name "${AZ_VM}-minecraft" \
    --resource-group "${AZ_VM_RG}" \
    --lb-name "${AZ_LB}" \
    --frontend-port "25565" \
    --backend-port "25565" \
    --frontend-ip-name "${AZ_LB}-public-ip" \
    --protocol "tcp" \
    --output none

printf "Create NSG ${AZ_VM}-nsg...\\n"
az network nsg create \
    --name "${AZ_VM}-nsg" \
    --resource-group "${AZ_VM_RG}" \
    --output none

printf "Create NSG rule to allow SSH...\\n"
az network nsg rule create \
    --name "Allow_SSH" \
    --nsg-name "${AZ_VM}-nsg" \
    --resource-group "${AZ_VM_RG}" \
    --priority "1000" \
    --direction "Inbound" \
    --source-address-prefixes "*" \
    --source-port-ranges "*" \
    --destination-address-prefixes "VirtualNetwork" \
    --destination-port-ranges "22" \
    --access "Allow" \
    --protocol "tcp" \
    --description "Allow SSH traffic from Any" \
    --output none

printf "Create NSG rule to allow Minecraft...\\n"
az network nsg rule create \
    --name "Allow_Minecraft" \
    --nsg-name "${AZ_VM}-nsg" \
    --resource-group "${AZ_VM_RG}" \
    --priority "1001" \
    --direction "Inbound" \
    --source-address-prefixes "*" \
    --source-port-ranges "*" \
    --destination-address-prefixes "VirtualNetwork" \
    --destination-port-ranges "25565" \
    --access "Allow" \
    --protocol "tcp" \
    --description "Allow Minecraft traffic from Any" \
    --output none

printf "Create NIC...\\n"
az network nic create \
    --name "${AZ_VM}-nic" \
    --resource-group "${AZ_VM_RG}" \
    --subnet "/subscriptions/${AZ_SUBSCRIPTION_ID}/resourceGroups/${AZ_VNET_RG}/providers/Microsoft.Network/virtualNetworks/${AZ_VNET}/subnets/${AZ_VNET_SUBNET_NAME}" \
    --public-ip-address "" \
    --network-security-group "${AZ_VM}-nsg" \
    --lb-address-pools "/subscriptions/${AZ_SUBSCRIPTION_ID}/resourceGroups/${AZ_VM_RG}/providers/Microsoft.Network/loadBalancers/${AZ_LB}/backendAddressPools/${AZ_VM}-backendpool" \
    --lb-inbound-nat-rules \
        "/subscriptions/${AZ_SUBSCRIPTION_ID}/resourceGroups/${AZ_VM_RG}/providers/Microsoft.Network/loadBalancers/${AZ_LB}/inboundNatRules/${AZ_VM}-ssh" \
        "/subscriptions/${AZ_SUBSCRIPTION_ID}/resourceGroups/${AZ_VM_RG}/providers/Microsoft.Network/loadBalancers/${AZ_LB}/inboundNatRules/${AZ_VM}-minecraft" \
    --output none

printf "Create ${AZ_VM} Azure Virtual Machine...\\n"
az vm create \
    --name "${AZ_VM}" \
    --resource-group "${AZ_VM_RG}" \
    --image "UbuntuLTS" \
    --size "Standard_B2s" \
    --accelerated-networking "true" \
    --nics "${AZ_VM}-nic" \
    --storage-sku "StandardSSD_LRS" \
    --admin-username "yandolfat" \
    --ssh-key-value "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCe0lgCF/ZKiUJnl8gbSQSKvzIiWZM8ZouxUxjmXGJIXvacmZCC/Ou7UvX5JMQFqUcYe63BSGOz93X2r4e17M++JbOR+ShloGS+4+w+wu6MAYaiVIC6/PmhSfyzFXEWuE+dLadNwJMF8ePUXqwYZntRy5Gahu1wYSkqaif3TNsDRCDYcd0viCOEmGN+NYeoNJwGQ9HIWJ29sY/BUZJWEVB0ZweTvNqwtl3bMvY/JHmEmEIYwdRcdROPEPmxcuBH81Tt2fsD9V7DYhyvz2lQPVJD++3jIZX2i9sPQj8SVJbo23xOZZykVIKU7WaztBtPPz3RdytBiyQ8sgNwKLbJX7Vv0+qY1no4xUnKwJPc5zfikje4rYxTksjIRg7igMNrCFGWZA75hb+Nm+HhQsKqVHtOIaw3P6j6slysQQ5MOQYTqg7k60yxTRGTv8Y6V45jrYWQg+vhKO4gzVTKsqrqJTRhJXU3vv//1NPW7ucNlNPCF8n0RyjXue6Y1Xr8rZv5QheLZvcHumd23pA+Z6aRA/Hd2VINy00PQz9dscOpWHpUiiu4HMPHLcLdlhaVMFr2otwB2749xHciZFCsWnprMGX6V3lVGHQ3OFfIBFz1ZVFG+eAbXmZZepdtwVJDidXDfvzAtMol/+PwVVUJgpA1a1dryyZkg9k2FbO1bSVolvmkpQ== Yves ANDOLFATTO" \
    --output none
printf "Done.\\n\\n"

# TOTO: Print the SAS Token
