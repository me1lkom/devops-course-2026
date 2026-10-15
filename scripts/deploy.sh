#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]

set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
LOCAL_DIR="$(git rev-parse --show-toplevel)/site/"

# 1. Разбор аргумента --dry-run
DRY_RUN=false

if [[ $# -gt 1 ]]; then
    echo "Ошибка: Слишком много аргументов" >&2
    exit 1
fi

if [[ $# -eq 1 ]]; then
    if  [[ "$1" == --dry-run ]]; then
        DRY_RUN=true
    else
        echo "Ошибка: Неизвестный аргумент" >&2
        exit 1
    fi
fi

echo "DRY_RUN=$DRY_RUN"

# 2. Проверки перед деплоем
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
        echo "Ошибка: файл site/index.html не найден" >&2
        exit 1
fi

if [[ -n "$(git -C "$LOCAL_DIR" status --porcelain --untracked-files=all)" ]]; then
    echo "Ошибка: в Git есть незакоммиченные изменения" >&2
    exit 1
fi

# 3. Синхронизация через rsync
RSYNC_OPTIONS=(-avz --delete --chmod=D755,F644)

if [[ "$DRY_RUN" == true ]]; then
    RSYNC_OPTIONS+=(--dry-run)
fi

rsync "${RSYNC_OPTIONS[@]}" \
    -e "ssh -o BatchMode=yes" \
    "$LOCAL_DIR" \
    "$REMOTE:$REMOTE_DIR/"

# 4. Обработка режима --dry-run
if [[ "$DRY_RUN" == true ]]; then
    echo "Пробный деплой завершён. Файлы на сервере не изменены."
    exit 0
fi

# 5. Проверка доступности сайта
if ! curl --fail --silent --show-error \
    --cacert "$CA_CERT" \
    --output /dev/null \
    "$SITE_URL"; then

    echo "Ошибка: сайт недоступен или проверка HTTPS не пройдена" >&2
    exit 1
fi

COMMIT=$(git -C "$LOCAL_DIR" rev-parse --short HEAD)

echo "Деплой успешно завершён. Коммит: $COMMIT"
exit 0
