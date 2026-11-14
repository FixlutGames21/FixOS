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
wget -f https://raw.githubusercontent.com/FixlutGames21/FixOS/main/installer.lua /home/installer.lua && /home/installer.lua
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

## FixPaint (1.0.0)

Растровий редактор: полотно малюється напівблоками (2 квадратні пікселі в клітинці), колір довільний 0xRRGGBB.

- Олівець, гумка, лінія, прямокутник, еліпс, заливка, піпетка; товщина 1-5; суцільні фігури
- Ліва кнопка миші - основний колір, права - фоновий; 32 кольори + власний HEX (клавіша K)
- Скасувати/повторити (Ctrl+Z / Ctrl+Y), зберігаються лише зміни, а не знімки
- Файли `.fpt` у `/pictures` (RLE, текстовий формат); подвійний клік у Explorer відкриває FixPaint
- На екрані T3 вмикається precise-режим миші (точність до півклітинки); на інших - клік зачіпає верхній піксель клітинки

## Device Manager (1.0.0)

Усі компоненти комп'ютера за категоріями, параметри системи (RAM, енергія, архітектура), живі дані GPU/екрана/дисків/EEPROM/Internet Card, список методів із документацією та повідомлення про підключення/відключення пристроїв.

## Update Center (2.0.0)

- Версії **окремих програм**: встановлена / на GitHub / стан (актуально, є оновлення, відсутні файли, змінено локально)
- Завантаження оновлень із GitHub: кожен файл перевіряється (розмір, Adler-32, компіляція Lua) ще до встановлення
- **Автоматична резервна копія** перед кожним оновленням (`/system/backups`, останні 5)
- **Відкат** до будь-якої копії; сам відкат теж створює копію, тож його можна скасувати
- Якщо підміна файлів не вдалась - автоматичний відкат; якщо перевірка не пройшла - система не змінюється
- Репозиторій і гілку можна змінити у вкладці «Журнал»

### Для автора репозиторію

Update Center працює за файлом `manifest.txt` у корені репозиторію. Після змін у файлах:

1. підніміть версію компонента у `tools/make_manifest.py` (інакше оновлення не буде видно);
2. запустіть `python3 tools/make_manifest.py`;
3. закомітьте `manifest.txt` разом зі змінами.

### 4.3.1 - курсор

- FixPaint: режим миші визначається за самими подіями (дробові координати = точний режим; цілі/центри клітинок = режим клітинок, пензель займає клітинку цілком)
- Нова бібліотека `system/lib/textfield.lua`: каретка, стрілки, Home/End/Delete, клік, прокрутка, Unicode; використовується в адресному рядку браузера, Update Center і діалогах FixPaint
