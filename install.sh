#!/bin/bash

# Скрипт установки монитора VPS

echo "=== Установка VPS Monitor ==="
echo ""

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Ошибка: Запустите скрипт с правами root (sudo ./install.sh)"
    exit 1
fi

# GitHub репозиторий
GITHUB_REPO="https://raw.githubusercontent.com/Killu-zl/vps-monitor/main"

# Скачиваем monitor.sh
echo "📥 Скачивание скрипта с GitHub..."
if ! curl -sSL "${GITHUB_REPO}/monitor.sh" -o /root/monitor.sh; then
    echo "❌ Ошибка: Не удалось скачать monitor.sh"
    echo "Проверьте подключение к интернету и URL репозитория"
    exit 1
fi

# Делаем исполняемым
chmod +x /root/monitor.sh

# Создаем символическую ссылку в /usr/local/bin для запуска из любой директории
echo "🔗 Создание ссылки в /usr/local/bin..."
ln -sf /root/monitor.sh /usr/local/bin/monitor

echo ""
echo "✅ Установка завершена!"
echo ""
echo "Использование:"
echo "  monitor          - запуск из любой директории"
echo ""
echo "Для удаления:"
echo "  rm /root/monitor.sh /usr/local/bin/monitor"
