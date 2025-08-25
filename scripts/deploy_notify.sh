#!/bin/bash
set -euo pipefail

STAGE=${2:-"CodeDeploy"}

# Emails
ALERT_EMAIL="nikhil.devops.moweb@gmail.com"
CC_EMAILS="dhaval.devops.moweb@gmail.com krish.devops.moweb@gmail.com"

# Timezone
export TZ="Asia/Kolkata"
export PATH=$PATH:/usr/local/bin:/usr/bin

# AWS Secrets Manager
SECRET_NAME="my-smtp-credentialss"
REGION="ap-south-1"

# 🔎 Get Deployment Status from AWS API instead of relying on env var
DEPLOYMENT_ID=${DEPLOYMENT_ID:-""}

if [ -n "$DEPLOYMENT_ID" ]; then
    STATUS_TEXT=$(aws deploy get-deployment \
      --deployment-id "$DEPLOYMENT_ID" \
      --region "$REGION" \
      --query "deploymentInfo.status" \
      --output text 2>/dev/null || echo "Unknown")
else
    STATUS_TEXT="Unknown"
fi

# Map to exit code style
case "$STATUS_TEXT" in
    Succeeded) STATUS=0 ;;
    Failed|Stopped) STATUS=1 ;;
    *) STATUS=1 ;;
esac

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
