#!/bin/bash

# Generate Auth Cookie
read -r -p "Enter admin username:" ADMIN_USER
read -r -s -p "Enter admin password:" ADMIN_PASSWORD

echo ">>>> Authenticating..."
# Authenticate using username / password and store cookies to /tmp/cookiejar
curl --cookie-jar /tmp/cookiejar --request POST "${CLOUDRON_APP_ORIGIN}/api/method/login" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  --data-raw "{\"usr\" : \"${ADMIN_USER}\", \"pwd\": \"${ADMIN_PASSWORD}\"}"

echo ">>>> Adding LDAP Configuration..."

# Modify LDAP Server Settings
curl --cookie /tmp/cookiejar --request PUT "https://${CLOUDRON_APP_ORIGIN}/api/resource/LDAP%20Settings/LDAP%20Settings" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  --data-raw "{
  \"docstatus\": 1,
  \"idx\": \"0\",
  \"enabled\": 1,
  \"ldap_directory_server\": \"OpenLDAP\",
  \"ssl_tls_mode\": \"Off\",
  \"require_trusted_certificate\": \"No\",
  \"ldap_groups\": [],
  \"ldap_server_url\": \"${CLOUDRON_LDAP_URL}\",
  \"base_dn\": \"${CLOUDRON_LDAP_BIND_DN}\",
  \"password\": \"${CLOUDRON_LDAP_BIND_PASSWORD}\",
  \"ldap_search_path_user\": \"${CLOUDRON_LDAP_USERS_BASE_DN}\",
  \"ldap_search_path_group\": \"${CLOUDRON_LDAP_GROUPS_BASE_DN}\",
  \"ldap_search_string\": \"(&(objectclass=user)(username={0}))\",
  \"ldap_email_field\": \"mail\",
  \"ldap_username_field\": \"username\",
  \"ldap_first_name_field\": \"givenName\",
  \"default_user_type\": \"Website User\",
  \"default_role\": \"Guest\"
}"

echo ">>>> Removing admin credentials..."
# Remove the cookiejar
rm /tmp/cookiejar

echo "LDAP Setup Complete"