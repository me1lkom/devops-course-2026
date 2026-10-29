
#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"

    if [[ "$actual" == "$expected" ]]; then
        echo " [OK] $desc"
        ((PASS++))
    else
        echo " [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"

# TODO 1: проверить, что порт SSH отличается от 22
ssh_port=$(sudo sshd -T | awk '/^port / {print $2}')
if [[ -n "$ssh_port" && "$ssh_port" != "22" ]]; then
    check "Порт SSH отличается от 22" "yes" "yes"
else
    check "Порт SSH отличается от 22" "yes" "no"
fi

# TODO 2: проверить, что MaxAuthTries равен 3
check "MaxAuthTries равен 3" "3" \
    "$(sudo sshd -T | awk '/^maxauthtries / {print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"

# TODO 3: проверить, что политика входящего трафика равна deny
check "Входящие соединения запрещены по умолчанию" "deny" \
    "$(sudo ufw status verbose | awk '/^Default:/ {print $2}')"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf " %s (uid=%s)\n",$1,$3}' /etc/passwd


echo "[4] Веб-сервер"

# Проверка 1. Состояние службы Nginx
check "Служба Nginx активна" "active" \
    "$(systemctl is-active nginx)"

# Проверка 2. Корректность конфигурации Nginx
if sudo nginx -t >/dev/null 2>&1; then
    check "Конфигурация Nginx корректна" "0" "0"
else
    check "Конфигурация Nginx корректна" "0" "1"
fi

# Проверка 3. Срок действия TLS-сертификата
if openssl x509 -in /etc/ssl/certs/devops.crt \
    -noout -checkend 2592000 >/dev/null 2>&1; then
    check "Сертификат действителен ещё 30 дней" "0" "0"
else
    check "Сертификат действителен ещё 30 дней" "0" "1"
fi

# Проверка 4. Права файлов сайта и закрытого ключа
if [[ -d /var/www/devops-site ]] \
    && [[ -z "$(find /var/www/devops-site -perm -o+w)" ]] \
    && [[ "$(sudo stat -c '%a' /etc/ssl/private/devops.key)" == "600" ]]; then
    check "Права файлов сайта и TLS-ключа корректны" "yes" "yes"
else
    check "Права файлов сайта и TLS-ключа корректны" "yes" "no"
fi


echo "[5] Контейнеризация"

# Проверка 1. Состояние службы Docker
check "Служба Docker активна" "active" \
    "$(systemctl is-active docker)"

# Проверка 2. Состояние PostgreSQL
check "Контейнер PostgreSQL здоров" "healthy" \
    "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null)"

# Проверка 3. Безопасность портов 5000 и 5432
unsafe_ports=$(ss -tlnH | awk '
    $4 ~ /:(5000|5432)$/ && $4 !~ /^127\.0\.0\.1:/ {print $4}
')

if [[ -z "$unsafe_ports" ]]; then
    check "Порты 5000 и 5432 не доступны на внешних адресах" "yes" "yes"
else
    check "Порты 5000 и 5432 не доступны на внешних адресах" "yes" "$unsafe_ports"
fi

# Проверка 4. Права файла .env
check "Права файла .env равны 600" "600" \
    "$(stat -c '%a' /home/devops/app/.env 2>/dev/null)"


echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1

