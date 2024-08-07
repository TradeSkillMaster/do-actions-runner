#!/usr/bin/env bash
set -eEuo pipefail

if [ -z "${APP_INSTALLATION_ID:-}" ]
then
  echo "APP_INSTALLATION_ID is required"
  exit 1
fi

if [ -z "${APP_CLIENT_ID:-}" ]
then
  echo "APP_CLIENT_ID is required"
  exit 1
fi

if [ -n "${ORG:-}" ]
then
  API_PATH=orgs/${ORG}
  CONFIG_PATH=${ORG}
elif [ -n "${OWNER:-}" ] && [ -n "${REPO:-}" ]
then
  API_PATH=repos/${OWNER}/${REPO}
  CONFIG_PATH=${OWNER}/${REPO}
else
  echo "[ORG] or [OWNER and REPO] is required"
  exit 1
fi

# See https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app

pem=$( echo $APP_PRIVATE_KEY | tr -d '\r' | base64 -d )

now=$(date +%s)
iat=$((${now} - 60)) # Issues 60 seconds in the past
exp=$((${now} + 600)) # Expires 10 minutes in the future

b64enc() { openssl base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n'; }

header_json='{
    "typ":"JWT",
    "alg":"RS256"
}'
# Header encode
header=$( echo -n "${header_json}" | b64enc )

payload_json='{
    "iat":'${iat}',
    "exp":'${exp}',
    "iss":"'${APP_CLIENT_ID}'"
}'
# Payload encode
payload=$( echo -n "${payload_json}" | b64enc )

# Signature
header_payload="${header}"."${payload}"
signature=$(
    openssl dgst -sha256 -sign <(echo -n "${pem}") \
    <(echo -n "${header_payload}") | b64enc
)

# Create JWT
APP_JWT="${header_payload}"."${signature}"

TOKEN=$(curl --request POST \
--url "https://api.github.com/app/installations/${APP_INSTALLATION_ID}/access_tokens" \
--header "Accept: application/vnd.github+json" \
--header "Authorization: Bearer ${APP_JWT}" \
--header "X-GitHub-Api-Version: 2022-11-28" | jq -r .token)

if [[ -z "${TOKEN}" ]] || [[ "${TOKEN}" = "null" ]]
then
  echo "Failed to get access token"
  exit 1
fi

RUNNER_TOKEN=$(curl -s -X POST -H "authorization: token ${TOKEN}" "https://api.github.com/${API_PATH}/actions/runners/registration-token" | jq -r .token)

if [ -z "${RUNNER_TOKEN}" ]
then
  echo "Failed to get runner token"
  exit 1
fi

cleanup() {
  ./config.sh remove --token "${RUNNER_TOKEN}"
}

./config.sh \
  --url "https://github.com/${CONFIG_PATH}" \
  --token "${RUNNER_TOKEN}" \
  --name "${NAME:-$(hostname)}" \
  --labels "self-hosted,ubuntu" \
  --unattended

trap 'cleanup' SIGTERM

./run.sh "$@" &

wait $!
