#!/bin/bash

# 1. Автоматично разпознаване на ОС и пътища
OS_TYPE=$(uname)

if [ "$OS_TYPE" == "Darwin" ]; then
    # Настройки за macOS
    export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    CURL_PATH=$(which curl)
    DATE_CMD="date"
elif [ "$OS_TYPE" == "Linux" ]; then
    # Настройки за Linux (Ubuntu/Debian)
    export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    CURL_PATH=$(which curl)
    DATE_CMD="date"
fi

# Преминаване в папката на скрипта
cd "$(dirname "$0")"

# 2. Зареждане на .env (с пълна поддръжка за macOS/Linux)
if [ -f ".env" ]; then
    # Четем .env, премахваме коментарите и експортираме променливите
    export $(grep -v '^#' .env | xargs)
fi

# Конфигурация
BOT_TOKEN="${BOT_TOKEN:-8352358532:AAGJnm4pNd0FEjr0hO3dEoLbKklWKK0dfmI}"
CHAT_ID="${CHAT_ID:-439455873}"
SITE_URL="https://eng.d-dimitrov.eu/Home-page"
STATE_FILE="/tmp/site_monitor_state"
ALERT_COOLDOWN=120

send_telegram() {
  local MESSAGE=$1
  $CURL_PATH -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
       --data-urlencode "chat_id=${CHAT_ID}" \
       --data-urlencode "text=${MESSAGE}" \
       --data-urlencode "parse_mode=HTML" > /dev/null
}

should_alert() {
  local alert_type=$1
  local current_time=$($DATE_CMD +%s)
  
  if [ -f "$STATE_FILE" ]; then
    local last_alert_time=$(grep "^${alert_type}:" "$STATE_FILE" | cut -d: -f2)
    if [ -n "$last_alert_time" ]; then
      local diff=$((current_time - last_alert_time))
      [ $diff -lt $ALERT_COOLDOWN ] && return 1
    fi
  fi
  
  grep -v "^${alert_type}:" "$STATE_FILE" 2>/dev/null > "${STATE_FILE}.tmp"
  echo "${alert_type}:${current_time}" >> "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
  return 0
}

mark_recovered() {
  local alert_type=$1
  if [ -f "$STATE_FILE" ] && grep -q "^${alert_type}:" "$STATE_FILE"; then
    send_telegram "✅ <b>САЙТЪТ Е ВЪЗСТАНОВЕН!</b>

🌐 URL: ${SITE_URL}
🕐 Време: $($DATE_CMD '+%Y-%m-%d %H:%M:%S')"
    grep -v "^${alert_type}:" "$STATE_FILE" 2>/dev/null > "${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
  fi
}

check_website() {
  local http_code=$($CURL_PATH -s -L -I -o /dev/null -w "%{http_code}" --max-time 10 "$SITE_URL")
  
  if [[ "$http_code" =~ ^(200|301|302)$ ]]; then
    mark_recovered "website"
  else
    if should_alert "website"; then
      local MSG="🚨 <b>САЙТЪТ Е НЕДОСТЪПЕН!</b>

🌐 URL: ${SITE_URL}
📊 Статус: ${http_code}
🕐 Време: $($DATE_CMD '+%Y-%m-%d %H:%M:%S')"
      send_telegram "$MSG"
    fi
  fi
}

check_website