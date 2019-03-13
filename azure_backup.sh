#!/bin/bash
# Backup files script for Ubuntu on Azure
# $1 = STORAGE_ACCOUNT_NAME
# $2 = STORAGE_ACCOUNT_KEY
# $3 = STORAGE_ACCOUNT_CONTAINER

set -eu -o pipefail

# Please edit according to your need.
BACKUP_DIR="/var/backups/minecraft"
FILES_DIR="/srv/minecraft_server"
LOG_DIR="/var/log/minecraft"
STORAGE_ACCOUNT_NAME=$1
STORAGE_ACCOUNT_KEY=$2
STORAGE_ACCOUNT_CONTAINER=$3
#-------------------------------------------------------------------------------

# Init
TMPDIR=$(mktemp -d /tmp/backup.XXXXXX)
BASENAME=$(basename $0)
TIMESTAMP=$(date +%s)-$(date "+%F")
BACKUP_FILE="${BACKUP_DIR}/full-backup-${TIMESTAMP}.tar.xz"
LOGFILE="${LOG_DIR}/${BASENAME}.log"

# Check backup destination is there
if [ ! -d "$LOG_DIR" ]; then
  mkdir -p $LOG_DIR
fi

# Utilities
write_log() {
  # Write a message to log file.
  message=$1
  timestamp=$(date "+[%Y-%m-%d %H:%M:%S.%N]")
  echo "${timestamp} ${message}" >> ${LOGFILE}
}

cleanup() {
  # Clean the temp files on exit.
  rm -rf "${TMPDIR}"
}
trap cleanup EXIT

# Status codes
rCodeBackup=0
rCodeFinalTar=0
rCodeUpload=0

# Install AzCopy
if [ ! -r /azcopy ]; then
  write_log "Install AzCopy..."
  wget -O /tmp/azcopy.tar.gz "https://aka.ms/downloadazcopy-v10-linux" \
  tar -xzvf /tmp/azcopy.tar.gz --strip-components=1 --wildcards 'azcopy_linux_amd64_*/azcopy' -C / \
  rm -f /tmp/azcopy.tar.gz
  write_log "AzCopy installed."
fi

# Backup begin
write_log "#### BACKUP BEGIN ####"

# Check backup destination is there
if [ ! -d "$BACKUP_DIR" ]; then
  mkdir -p $BACKUP_DIR
fi

# Application backup
write_log "Copy files."
systemctl stop minecraft-server
cp -a "${FILES_DIR}" "${TMPDIR}" || rCodeBackup=$?
systemctl start minecraft-server
if [ $rCodeBackup -ne 0 ]; then
  write_log "Unable to backup the files!"
  write_log "!!!! BACKUP FAILED !!!!"
  exit 2
fi

# Final archiving
write_log "Archive all in \"${BACKUP_FILE}\"."
tar Jcf "${BACKUP_FILE}" ${TMPDIR} >/dev/null 2>&1 || rCodeFinalTar=$?
if [ $rCodeFinalTar -ne 0 ]; then
  write_log "Unable to create the final archive!"
  write_log "!!!! BACKUP FAILED !!!!"
  exit 2
fi

# Upload the archive
write_log "Upload \"${BACKUP_FILE}\" into \"https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net/${STORAGE_ACCOUNT_CONTAINER}\"."
/azcopy \
  --source ${BACKUP_FILE} \
  --destination "https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net/${STORAGE_ACCOUNT_CONTAINER}/${BACKUP_FILE}" \
  --dest-key "${STORAGE_ACCOUNT_KEY}" >/dev/null 2>&1 || rCodeUpload=$?
if [ $rCodeUpload -ne 0 ]; then
  write_log "Unable to upload the final archive into Azure!"
  write_log "!!!! BACKUP FAILED !!!!"
  exit 2
fi

write_log "#### BACKUP END ####"
exit 0
