#!/bin/bash
set -euo pipefail

ARG_STATUS=${1:-auto}   # 0=success,1=failure,auto=detect
STAGE=${2:-"CodeDeploy"}

ALERT_EMAIL="nikhil.devops.moweb@gmail.com"
CC_EMAILS="dhaval.devops.moweb@gmail krish.devops.moweb@gmail.com"

export TZ="Asia/Kolkata"
export PATH=$PATH:/usr/local/bin:/usr/bin

# AWS Secrets
SECRET_NAME="my-smtp-credentialss"
REGION="ap-south-1"
SECRETS_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --region "$REGION" \
  --query SecretString --output text)
SMTP_USER=$(echo "$SECRETS_JSON" | jq -r .SMTP_USER)
SMTP_PASS=$(echo "$SECRETS_JSON" | jq -r .SMTP_PASS)

cat > /tmp/msmtprc <<EOF
defaults
auth on
tls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
account gmail
host smtp.gmail.com
port 587
from $SMTP_USER
user $SMTP_USER
password $SMTP_PASS
account default : gmail
EOF
chmod 600 /tmp/msmtprc

# Detect status
if [ "$ARG_STATUS" == "auto" ]; then
    if [ "${DEPLOYMENT_STATUS:-Succeeded}" == "Succeeded" ]; then
        STATUS=0
        # Detect rollback by comparing revision (optional)
        if [ "${ROLLED_BACK:-0}" == "1" ]; then
            STATUS=1
            STAGE="CodeDeploy (Rolled back)"
        fi
    else
        STATUS=1
    fi
else
    STATUS=$ARG_STATUS
fi

BODY="Stage: $STAGE
Status: $( [ $STATUS -eq 0 ] && echo Success || echo Failed )
Time: $(date '+%Y-%m-%d %H:%M:%S %Z')
Deployment ID: ${DEPLOYMENT_ID:-N/A}
Application: ${APPLICATION_NAME:-N/A}
Description: CodeDeploy has completed its execution."

send_mail() {
    local SUBJECT="$1"
    local BODY="$2"
    {
        echo "Subject: $SUBJECT"
        echo "From: $SMTP_USER"
        echo "To: $ALERT_EMAIL"
        for cc in $CC_EMAILS; do echo "Cc: $cc"; done
        echo
        echo "$BODY"
    } | msmtp -C /tmp/msmtprc -t || echo "⚠️ Email sending failed"
}

if [ "$STATUS" -eq 0 ]; then
    send_mail "✅ $STAGE Success" "$BODY"
else
    send_mail "❌ $STAGE Failed" "$BODY"
fi
