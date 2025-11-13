#!/bin/bash

# Зареждане на променливи
SITE_URL="https://eng.d-dimitrov.eu/Home-page"  # Твоят домейн
STATE_FILE="/tmp/site_monitor_state"
ALERT_COOLDOWN=300  # 5 минути между повтарящи се алерти
# Променливи от GitHub Secrets
: "${BOT_TOKEN:?Missing BOT_TOKEN}"
: "${CHAT_ID:?Missing CHAT_ID}"
: "${LOCAL_DB_HOST:?Missing LOCAL_DB_HOST}"
: "${LOCAL_DB_USER:?Missing LOCAL_DB_USER}"
: "${LOCAL_DB_PASSWORD:?Missing LOCAL_DB_PASSWORD}"
: "${LOCAL_DB_PORT:?Missing LOCAL_DB_PORT}"
# Telegram функция
send_telegram() {
  local MESSAGE=$1
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
       -d chat_id="${CHAT_ID}" \
       -d text="${MESSAGE}" \
       -d parse_mode="Markdown" > /dev/null 2>&1
}

# Проверка дали трябва да изпратим алерт (cooldown)
should_alert() {
  local alert_type=$1
  local current_time=$(date +%s)
  
  if [ -f "$STATE_FILE" ]; then
    local last_alert_time=$(grep "^${alert_type}:" "$STATE_FILE" | cut -d: -f2)
    if [ -n "$last_alert_time" ]; then
      local diff=$((current_time - last_alert_time))
      if [ $diff -lt $ALERT_COOLDOWN ]; then
        return 1  # Не изпращай алерт
      fi
    fi
  fi
  
  # Запази времето на последния алерт
  grep -v "^${alert_type}:" "$STATE_FILE" 2>/dev/null > "${STATE_FILE}.tmp"
  echo "${alert_type}:${current_time}" >> "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
  
  return 0  # Изпрати алерт
}

# Маркирай възстановяване
mark_recovered() {
  local alert_type=$1
  grep -v "^${alert_type}:" "$STATE_FILE" 2>/dev/null > "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# 1️⃣ Проверка на сайта
check_website() {
  local http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$SITE_URL")
  
  if [ "$http_code" != "200" ] && [ "$http_code" != "301" ] && [ "$http_code" != "302" ] && [ "$http_code" != "308" ]; then
    if should_alert "website"; then
      send_telegram "🚨 *САЙТЪТ Е НЕДОСТЪПЕН!*\n\n🌐 URL: \`${SITE_URL}\`\n📊 HTTP код: \`${http_code}\`\n🕐 Време: \`$(date '+%Y-%m-%d %H:%M:%S')\`\n\n⚡ *Действия:*\n1️⃣ Провери сървъра\n2️⃣ Провери Nginx/PM2\n3️⃣ Пренасочи трафика към Vercel при нужда"
    fi
    return 1
  else
    if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ] || [ "$http_code" = "308" ]; then
      send_telegram "✅ *САЙТЪТ Е ДОСТЪПЕН!*\n\n🌐 URL: \`${SITE_URL}\`\n📊 HTTP код: \`${http_code}\`\n🕐 Време: \`$(date '+%Y-%m-%d %H:%M:%S')\`"
    fi
    mark_recovered "website"
    return 0
  fi
}

# 2️⃣ Проверка на PostgreSQL
# check_database() {
#   if ! PGPASSWORD="$LOCAL_DB_PASSWORD" psql -h "$LOCAL_DB_HOST" -U "$LOCAL_DB_USER" -p "$LOCAL_DB_PORT" -d "prod_db" -c "SELECT 1;" > /dev/null 2>&1; then
#     if should_alert "database"; then
#       send_telegram "🚨 *БАЗАТА ДАННИ НЕ ОТГОВАРЯ!*\n\n💾 Host: \`${LOCAL_DB_HOST}\`\n💾 Database: \`prod_db\`\n🕐 Време: \`$(date '+%Y-%m-%d %H:%M:%S')\`\n\n⚡ *Действия:*\n1️⃣ Провери PostgreSQL: \`sudo systemctl status postgresql\`\n2️⃣ Рестартирай: \`sudo systemctl restart postgresql\`\n3️⃣ Използвай Neon DB ако е необходимо"
#     fi
#     return 1
#   else
#     if [ -f "$STATE_FILE" ] && grep -q "^database:" "$STATE_FILE"; then
#       send_telegram "✅ *БАЗАТА ДАННИ Е ВЪЗСТАНОВЕНА!*\n\n💾 Database: \`prod_db\`\n🕐 Време: \`$(date '+%Y-%m-%d %H:%M:%S')\`"
#       mark_recovered "database"
#     fi
#     return 0
#   fi
# }

# 3️⃣ Проверка на дисково пространство
# check_disk_space() {
#   local usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
  
#   if [ "$usage" -gt 85 ]; then
#     if should_alert "disk"; then
#       send_telegram "⚠️ *ДИСКОВОТО ПРОСТРАНСТВО Е КРИТИЧНО!*\n\n💿 Използвано: \`${usage}%\`\n🕐 Време: \`$(date '+%Y-%m-%d %H:%M:%S')\`\n\n⚡ *Действия:*\n1️⃣ Изтрий стари логове\n2️⃣ Провери големи файлове: \`du -sh /* | sort -rh | head -10\`"
#     fi
#     return 1
#   else
#     mark_recovered "disk"
#     return 0
#   fi
# }

# 4️⃣ Проверка на RAM
# check_memory() {
#   local mem_usage=$(free | awk 'NR==2 {printf "%.0f", $3/$2*100}')
  
#   if [ "$mem_usage" -gt 90 ]; then
#     if should_alert "memory"; then
#       send_telegram "⚠️ *ПАМЕТТА Е КРИТИЧНА!*\n\n🧠 Използвана RAM: \`${mem_usage}%\`\n🕐 Време: \`$(date '+%Y-%m-%d %H:%M:%S')\`\n\n⚡ *Действия:*\n1️⃣ Провери процеси: \`top\`\n2️⃣ Рестартирай услуги при нужда"
#     fi
#     return 1
#   else
#     mark_recovered "memory"
#     return 0
#   fi
# }

# 5️⃣ Проверка на Node.js процес (PM2)
# check_nodejs() {
#   if ! pm2 list | grep -q "online"; then
#     if should_alert "nodejs"; then
#       send_telegram "🚨 *NODE.JS ПРОЦЕСЪТ НЕ РАБОТИ!*\n\n🕐 Време: \`$(date '+%Y-%m-%d %H:%M:%S')\`\n\n⚡ *Действия:*\n1️⃣ Провери PM2: \`pm2 status\`\n2️⃣ Рестартирай: \`pm2 restart all\`\n3️⃣ Провери логове: \`pm2 logs\`"
#     fi
#     return 1
#   else
#     if [ -f "$STATE_FILE" ] && grep -q "^nodejs:" "$STATE_FILE"; then
#       send_telegram "✅ *NODE.JS ПРОЦЕСЪТ Е ВЪЗСТАНОВЕН!*\n\n🕐 Време: \`$(date '+%Y-%m-%d %H:%M:%S')\`"
#       mark_recovered "nodejs"
#     fi
#     return 0
#   fi
# }

# Изпълни всички проверки
echo "=== Monitor check started at $(date) ==="

check_website
website_status=$?
# Ако скрипта се изпълни на сървър с база данни, диск, памет и Node.js, махни коментарите от следващите редове
# check_database
# db_status=$?

# check_disk_space
# disk_status=$?

# check_memory
# mem_status=$?

# check_nodejs
# nodejs_status=$?

# Ако всичко е OK и е имало проблеми преди
if [ $website_status -eq 0 ]; then
    # Имало е проблеми, сега всичко е ОК
    send_telegram "✅ *Всички системи работят нормално*\n\n🌐 URL: \`${SITE_URL}\`\n🕐 Време: \`$(date '+%Y-%m-%d %H:%M:%S')\`"
    echo "All systems operational"
  fi
fi

echo "=== Monitor check completed at $(date) ==="