#!/bin/bash
set -euo pipefail

# -------------------------------
# Arguments
# -------------------------------
ARG_STATUS=${1:-auto}          # "0" = success, "1" = fail, "auto" = detect, "early" = early failure
STAGE=${2:-"CodeDeploy"}

# -------------------------------
# Email config
# -------------------------------
ALERT_EMAIL="nikhil.devops.moweb@gmail.com"
CC_EMAILS="dhaval.devops.moweb@gmail krish.devops.moweb@gmail"

# Timezone
export TZ="Asia/Kolkata"

# AWS CLI PATH
export PATH=$PATH:/usr/local/bin:/usr/bin

# Secrets Manager
SECRET_NAME="my-smtp-credentialss"
REGION="ap-south-1"

# -------------------------------
# Track sent mails per deployment
# -------------------------------
MAIL_TRACK_FILE="/tmp/deploy_mail_sent.txt"
DEPLOY_ID="${DEPLOYMENT_ID:-N/A}"

mkdir -p $(dirname "$MAIL_TRACK_FILE")
touch "$MAIL_TRACK_FILE"

# Prevent duplicate mail for same deployment
if grep -q "$DEPLOY_ID" "$MAIL_TRACK_FILE"; then
    echo "⚠️ Mail already sent for deployment $DEPLOY_ID, skipping."
    exit 0
fi

# -------------------------------
# Determine deployment status
# -------------------------------
if [ "$ARG_STATUS" == "auto" ]; then
    if [ "${DEPLOYMENT_STATUS:-Succeeded}" == "Succeeded" ]; then
        STATUS=0
    else
        STATUS=1
    fi
elif [ "$ARG_STATUS" == "early" ]; then
    STATUS=1
else
    STATUS=$ARG_STATUS
fi

# -------------------------------
# Fetch Gmail creds from Secrets Manager
# -------------------------------
SECRETS_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --region "$REGION" \
  --query SecretString \
  --output text)

SMTP_USER=$(echo "$SECRETS_JSON" | jq -r .SMTP_USER)
SMTP_PASS=$(echo "$SECRETS_JSON" | jq -r .SMTP_PASS)

# -------------------------------
# Temporary msmtp config
# -------------------------------
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

# -------------------------------
# Compose email
# -------------------------------
if [ "$STATUS" -eq 0 ]; then
    STATUS_TEXT="Success"
else
    STATUS_TEXT="Failed"
fi

BODY="Stage: $STAGE
Status: $STATUS_TEXT
Time: $(date '+%Y-%m-%d %H:%M:%S %Z')
Deployment ID: $DEPLOY_ID
Application: ${APPLICATION_NAME:-N/A}
Description: CodeDeploy has completed its execution."

# -------------------------------
# Send email function
# -------------------------------
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

# -------------------------------
# Send the mail
# -------------------------------
if [ "$STATUS" -eq 0 ]; then
    send_mail "✅ $STAGE Success" "$BODY"
else
    send_mail "❌ $STAGE Failed" "$BODY"
fi

# Mark deployment ID as mail sent
echo "$DEPLOY_ID" >> "$MAIL_TRACK_FILE"
