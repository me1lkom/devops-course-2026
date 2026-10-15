
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

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1

