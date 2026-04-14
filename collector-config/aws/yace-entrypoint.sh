#!/bin/sh
# YACE entrypoint — reads AWS credentials from Docker secret
# Ticket #1009, #1018
# The secret is mounted at /run/secrets/aws_credentials

SECRET_FILE="/run/secrets/aws_credentials"

if [ -f "$SECRET_FILE" ]; then
  # Extract credentials from JSON (using grep+sed since the image is minimal)
  export AWS_ACCESS_KEY_ID=$(grep -o '"aws_access_key_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$SECRET_FILE" | sed 's/.*: *"//;s/"$//')
  export AWS_SECRET_ACCESS_KEY=$(grep -o '"aws_secret_access_key"[[:space:]]*:[[:space:]]*"[^"]*"' "$SECRET_FILE" | sed 's/.*: *"//;s/"$//')
  REGION=$(grep -o '"aws_region"[[:space:]]*:[[:space:]]*"[^"]*"' "$SECRET_FILE" | sed 's/.*: *"//;s/"$//')
  if [ -n "$REGION" ]; then
    export AWS_DEFAULT_REGION="$REGION"
  fi
fi

# Fall through to default region from env if not in secret
: "${AWS_DEFAULT_REGION:=us-east-1}"
export AWS_DEFAULT_REGION

# prometheuscommunity image places the binary at /bin/yace
exec /bin/yace --config.file=/config/yace-config.yaml "$@"
