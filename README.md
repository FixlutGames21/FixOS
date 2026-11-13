# FixOS

A lightweight operating system for the OpenComputers Minecraft mod.

## Features

* Easy installation
* User-friendly graphical interface
* Designed specifically for OpenComputers
* Open source

## Requirements

* Internet Card
* Hard Disk Drive (tier 2)

## Installation

Download the installer:

```lua
wget -f https://raw.githubusercontent.com/FixlutGames21/FixOS/main/installer.lua /home/installer.lua
```

### Installation Steps

1. Run the installer.
2. Follow the on-screen instructions.
3. Click the blue buttons when prompted.
4. Wait for the installation to complete.
5. Enjoy using FixOS.

## Project Status

FixOS is currently under development. New features, improvements, and bug fixes are added regularly.

## Contributing

Contributions, bug reports, and suggestions are welcome.

## Browser (4.2.0)

Браузер переписано: працює з Internet Card, показує сторінки з клікабельними посиланнями.

- HTTP/HTTPS, редіректи (в т.ч. http <-> https), ліміт розміру за вільною RAM
- Автовідкат на http:// при помилці сертифіката (PKIX/SSL на старій Java)
- Запасний TCP-режим для http://, якщо HTTP вимкнено в конфігу сервера
- Адресний рядок = пошук (DuckDuckGo), кирилиця, вставка Shift+Insert
- Режим Reader [M] через r.jina.ai (сторонній сервіс!) для сайтів на JavaScript
- about:net - діагностика мережі, about:help - довідка

Нові файли: `system/lib/net.lua`, `system/lib/html.lua`.
Змінено: `desktop.lua` (подія clipboard, закриття вікна звільняє з'єднання), `settings.lua` (перевірка оновлень), `installer.lua`.
