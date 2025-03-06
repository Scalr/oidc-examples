#!/usr/bin/env bash

echo "Exchanging OIDC ID Token for Scalr Token..."

RESPONSE=$(curl -sw "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d '{"id_token": "'"${GITLAB_OIDC_TOKEN}"'", "service-account-email": "'"${SCALR_SA_EMAIL}"'"}' \
        "https://$SCALR_HOSTNAME/api/iacp/v3/service-accounts/assume")

HTTP_BODY=$(echo "$RESPONSE" | sed '$ d')
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)


if [ "$HTTP_CODE" -ne 200 ]; then
    echo "❌ Error: Failed to exchange token with Scalr"
    exit 1
fi

SCALR_TOKEN=$(echo "$HTTP_BODY" | jq -r '."access-token"')

if [ -z "$SCALR_TOKEN" ] || [ "$SCALR_TOKEN" == "null" ]; then
    echo "❌ Error: Scalr Token retrieval failed!"
    exit 1
fi

echo "Authorizing tofu CLI...."
mkdir -p ~/.terraform.d
echo "{\"credentials\": {\"${SCALR_HOSTNAME}\": {\"token\": \"${SCALR_TOKEN}\"}}}" > ~/.terraform.d/credentials.tfrc.json

echo "Environment prepared!"
