#!/bin/bash

LOCAL=$(dirname "$0")
cd "$LOCAL"
cd ../

ACTIVE_RESPONSE_ROOT=$(pwd)

read INPUT_JSON
FILENAME=$(echo "$INPUT_JSON" | jq -r .parameters.alert.data.virustotal.source.file)
COMMAND=$(echo "$INPUT_JSON" | jq -r .command)
LOG_FILE="${ACTIVE_RESPONSE_ROOT}/../logs/active-responses.log"

#------------------------ Analyze command -------------------------#
if [ "$COMMAND" = "add" ]
then
 # Send control message to execd
 printf '{"version":1,"origin":{"name":"remove-threat","module":"active-response"},"command":"check_keys", "parameters":{"keys":[]}}\n'

 read RESPONSE
 COMMAND2=$(echo "$RESPONSE" | jq -r .command)
 if [ "$COMMAND2" != "continue" ]
 then
  echo "$(date '+%Y/%m/%d %H:%M:%S') $0: $INPUT_JSON Remove threat active response aborted" >> "$LOG_FILE"
  exit 0;
 fi
fi

# Removing file
if [ -z "$FILENAME" ] || [ "$FILENAME" = "null" ] || [ ! -f "$FILENAME" ] || [ -L "$FILENAME" ]; then
 echo "$(date '+%Y/%m/%d %H:%M:%S') $0: Rejected unsafe or missing threat path" >> "$LOG_FILE"
 exit 1
fi

rm -f -- "$FILENAME"
if [ $? -eq 0 ]; then
 echo "$(date '+%Y/%m/%d %H:%M:%S') $0: $INPUT_JSON Successfully removed threat" >> "$LOG_FILE"
else
 echo "$(date '+%Y/%m/%d %H:%M:%S') $0: $INPUT_JSON Error removing threat" >> "$LOG_FILE"
fi

exit 0;
