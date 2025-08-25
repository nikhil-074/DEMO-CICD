#!/bin/bash
set -euo pipefail

ARG_STATUS=${1:-auto}      # "0", "1", or "auto"
STAGE=${2:-"CodeDeploy"}

# Emails
ALERT_EMAIL="nikhil.devops.moweb@gmail.com"
CC_EMAILS="dhaval.devops.moweb@gmail krish.devops.moweb@gmail"

# Timezone
export TZ="Asia/Kolkata"
export PATH=$PATH:/usr/local/bin:/usr/bin

# AWS Secrets Manager
SECRET_NAME="my-smtp-credentialss"
REGION="ap-south-1"

# Determine final deployment status
if [ "$ARG_STATUS" == "auto" ]; then
    case "${DEPLOYMENT_STATUS:-Succeeded}" in
        Succeeded)
            STATUS=0
            STATUS_TEXT="Success"
            ;;
        Failed)
            STATUS=1
            STATUS_TEXT="Failed"
            ;;
        Stopped)
            STATUS=1
            STATUS_TEXT="Rolled back"
            ;;
        *)
            STATUS=1
            STATUS_TEXT="Unknown"
            ;;
    esac
else
    STATUS=$ARG_STATUS
    STATUS_TEXT=$([ "$STATUS" -eq 0 ] && echo "Success" || echo "Failed")
fi

# Fetch Gmail credentials
SECRETS_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --region "$REGION" \
  --query SecretString \
  --output text)
SMTP_USER=$(echo "$SECRETS_JSON" | jq -r .SMTP_USER)
SMTP_PASS=$(echo "$SECRETS_JSON" | jq -r .SMTP_PASS)

# Temporary msmtp config
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

# Compose email
BODY="Stage: $STAGE
Status: $STATUS_TEXT
Time: $(date '+%Y-%m-%d %H:%M:%S %Z')
Deployment ID: ${DEPLOYMENT_ID:-N/A}
Application: ${APPLICATION_NAME:-N/A}
Description: CodeDeploy has completed its execution."

# Send function
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

# Send email
if [ "$STATUS" -eq 0 ]; then
    send_mail "✅ $STAGE Success" "$BODY"
else
    send_mail "❌ $STAGE $STATUS_TEXT" "$BODY"
fi
