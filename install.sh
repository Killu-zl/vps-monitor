#!/bin/bash

# Скрипт установки монитора VPS

echo "=== Установка VPS Monitor ==="
echo ""

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Ошибка: Запустите скрипт с правами root (sudo ./install.sh)"
    exit 1
fi

# Копируем скрипт в /root
echo "📁 Копирование скрипта в /root..."
cp monitor.sh /root/monitor.sh
chmod +x /root/monitor.sh

# Создаем символическую ссылку в /usr/local/bin для запуска из любой директории
echo "🔗 Создание ссылки в /usr/local/bin..."
ln -sf /root/monitor.sh /usr/local/bin/monitor

echo ""
echo "✅ Установка завершена!"
echo ""
echo "Использование:"
echo "  monitor          - запуск из любой директории"
echo "  /root/monitor.sh - прямой запуск"
echo ""
echo "Для удаления:"
echo "  rm /root/monitor.sh /usr/local/bin/monitor"
