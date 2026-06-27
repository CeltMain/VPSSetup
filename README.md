<div align="center">
  <img width="280" height="280" alt="IMG_20250403_225327_985 (3)" src="https://github.com/user-attachments/assets/9c7ff9b4-0ef0-452c-9600-1d5fff07a83d" />
  
# Что делает скрипт?
</div>

### 🔗 VPS Setup
```bash
bash <(curl -Ls https://raw.githubusercontent.com/CeltMain/VPSSetup/refs/heads/main/vpssetup.sh)
```

<div align="center">
### Базовая, минимальная автоматизация настройки свежей VPS.

</div>

- Позволяет установить порт SSH на выбор
- Позволяет создать настраиваемый файл подкачки [Default: 2]
- Настройка DNS over TLS [Default: Quad9]
- Конфигурация и включение UFW
    + открытие 2 портов: выбранный SSH и 443/tcp (остальное без изменений)
    + отключение создания правил для IPv6
- Включение автообновления патчей безопасности
***
- Завершающий этап с очисткой старых зависимостей


### 🔗 SSH-Tunnel Setup
```bash
bash <(curl -Ls https://raw.githubusercontent.com/CeltMain/VPSSetup/refs/heads/main/tunnelsetup.sh)
```

<div align="center">
### Автоматизация создания изолированного пользователя для SSH-туннелей.
</div>
