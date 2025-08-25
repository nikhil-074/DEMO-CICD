#!/bin/bash
set -euo pipefail

SCRIPT=$1
STAGE=$2

DEPLOY_STATUS_FILE="/tmp/deploy_status"

notify() {
    STATUS=$1
    BODY="Stage: $STAGE
Status: $STATUS
Time (UTC): $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Deployment ID: ${DEPLOYMENT_ID:-N/A}
Application: ${APPLICATION_NAME:-N/A}"

    # send mail (reuse deploy_notify.sh for actual sending)
    /opt/deploy/deploy_notify.sh "$STATUS" "$STAGE" "$BODY"
}

if [ "$SCRIPT" == "success_marker" ]; then
    # Only reached if no earlier failure
    notify "Success"
    exit 0
fi

if bash "$SCRIPT"; then
    echo "$STAGE OK" >> "$DEPLOY_STATUS_FILE"
else
    notify "Failed"
    exit 1
fi

