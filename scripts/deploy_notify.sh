#!/bin/bash
STATUS=$1       # "Success" or "Failed"
STAGE=$2
BODY=$3
...
send_mail "[$STATUS] $STAGE" "$BODY"
