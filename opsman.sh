#!/bin/bash

set -e

shopt -s expand_aliases

alias uaac='BUNDLE_GEMFILE=/home/tempest-web/tempest/web/vendor/uaac/Gemfile bundle exec uaac'

usage_and_exit() {
  cat <<EOF
Usage: opsman <command> <internal|sso> [options]
Examples:
  opsman upload internal cf-1.8.5-build.4.pivotal
  opsman upload sso cf-1.8.5-build.4.pivotal
EOF
  exit 1
}

error_and_exit() {
  echo "$1" && exit 1
}

login_to_uaac() {
  uaac target https://localhost/uaa --skip-ssl-validation

  if [ "internal" = "$AUTH" ]; then

    local OPSMAN_USER=
    read -r -p "Ops Manager User: " OPSMAN_USER

    local OPSMAN_PASS=
    read -r -s -p "Ops Manager Pass: " OPSMAN_PASS

    uaac token owner get opsman "$OPSMAN_USER" -p "$OPSMAN_PASS" -s ''

    echo "User $OPSMAN_USER logged in successfully."
  elif [ "sso" = "$AUTH" ]; then
    uaac token sso get opsman -s ''
  fi
}

is_valid_access_token() {
  local UAA_ACCESS_TOKEN=$1
  [ -n "$UAA_ACCESS_TOKEN" ] || return 1

  local STATUS_CODE=$(curl http://localhost/uaa/check_token -k -L -G \
    -s -o /dev/null -w "%{http_code}" \
    -u "opsman:" \
    -d token_type=bearer \
    -d token="$UAA_ACCESS_TOKEN")

    [ "200" = "$STATUS_CODE" ]
}

upload_to_opsman() {
  local LOCAL_FILE_NAME=$1
  
  if [ -z "$LOCAL_FILE_NAME" ]; then
    read -r -p "Local file name: " LOCAL_FILE_NAME
  fi

  if [ ! -f "$LOCAL_FILE_NAME" ]; then
    error_and_exit "Invalid file: $LOCAL_FILE_NAME"
  fi

  local UAA_ACCESS_TOKEN=$(uaac context | grep access_token | awk '{ print $2 }')

  if ! is_valid_access_token "$UAA_ACCESS_TOKEN"; then
    login_to_uaac
    UAA_ACCESS_TOKEN=$(uaac context | grep access_token | awk '{ print $2 }')
  fi

  if [[ $LOCAL_FILE_NAME == *"bosh-stemcell"* ]]; then
    #stemcell upload
    echo "uploading stemcell $LOCAL_FILE_NAME"
    curl "https://localhost/api/v0/stemcells" \
       -k -# -o /dev/null \
       -X POST \
       -H "Authorization: Bearer $UAA_ACCESS_TOKEN" \
       -F "stemcell[file]=@$LOCAL_FILE_NAME"
  else
    echo "upload services $LOCAL_FILE_NAME"
    curl "https://localhost/api/v0/available_products" \
       -k -# -o /dev/null \
       -X POST \
       -H "Authorization: Bearer $UAA_ACCESS_TOKEN" \
       -F "product[file]=@$LOCAL_FILE_NAME"
  fi
}

upload_all_to_opsman() {
  for filename in $1; do
    upload_to_opsman $filename
  done
}

CMD=$1
shift
AUTH=$1
shift
ARG=$*

if [[ "internal" != "$AUTH" && "sso" != "$AUTH" ]]; then
  usage_and_exit
fi

if [ "upload" = "$CMD" ]; then
  upload_all_to_opsman "$ARG"
else
  usage_and_exit
fi
