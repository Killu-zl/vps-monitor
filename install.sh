#!/bin/bash

# Скрипт установки/обновления монитора VPS

echo "=== Установка VPS Monitor ==="
echo ""

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Ошибка: Запустите скрипт с правами root (sudo ./install.sh)"
    exit 1
fi

# GitHub репозиторий
GITHUB_REPO="https://raw.githubusercontent.com/Killu-zl/vps-monitor/main"

# Проверяем существует ли файл
if [ -f /root/monitor.sh ]; then
    echo "📝 Обнаружена существующая версия, обновление..."
else
    echo "📥 Установка новой версии..."
fi

# Скачиваем monitor.sh (с перезаписью)
if ! curl -sSL "${GITHUB_REPO}/monitor.sh" -o /root/monitor.sh; then
    echo "❌ Ошибка: Не удалось скачать monitor.sh"
    echo "Проверьте подключение к интернету и URL репозитория"
    exit 1
fi

# Делаем исполняемым
chmod +x /root/monitor.sh

# Создаем символическую ссылку в /usr/local/bin для запуска из любой директории
echo "🔗 Настройка команды monitor..."
ln -sf /root/monitor.sh /usr/local/bin/monitor

echo ""
echo "✅ Установка/обновление завершено!"
echo ""
echo "Использование:"
echo "  monitor          - запуск из любой директории"
echo ""
echo "Для обновления:"
echo "  curl -sSL ${GITHUB_REPO/monitor.sh/install.sh} | sudo bash"
echo ""
echo "Для удаления:"
echo "  rm /root/monitor.sh /usr/local/bin/monitor"
