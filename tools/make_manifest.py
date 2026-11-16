#!/usr/bin/env python3
"""
Генератор manifest.txt для FixOS Update Center.

Запускайте з кореня репозиторію ПЕРЕД git commit/push:

    python3 tools/make_manifest.py

Що робить: рахує розмір і контрольну суму Adler-32 кожного файлу та
записує їх у manifest.txt разом із версіями компонентів. Update Center
порівнює версії компонентів і перевіряє кожен завантажений файл
(розмір + Adler-32 + компіляція Lua) - тому manifest.txt мусить
відповідати файлам у репозиторії.

ВАЖЛИВО: змінили програму - підніміть її версію в COMPONENTS нижче,
інакше Update Center не побачить оновлення (версії порівнюються числами).

CRLF: GitHub віддає файли так, як вони лежать у репозиторії (з
.gitattributes "text=auto" - це LF). Тому розміри рахуються після
заміни CRLF -> LF. Якщо у вас файли в репозиторії з CRLF - запустіть
з прапорцем --raw.
"""
import glob
import os
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

OS_VERSION = "4.3.4"

# (id, назва, версія, прапорці, залежності, [шаблони файлів])
COMPONENTS = [
    ("core", "FixOS Core", "4.3.4", "reboot", "", [
        "boot/init.lua", "system/ui.lua", "system/lang.lua", "system/version.lua",
        "system/desktop.lua", "system/language/*.lang", "system/icons/*.png", "version.txt"]),
    ("netlib", "Network library", "1.0.0", "", "", ["system/lib/net.lua"]),
    ("htmllib", "HTML renderer", "1.0.0", "", "", ["system/lib/html.lua"]),
    ("textlib", "Text field (cursor)", "1.0.0", "", "", ["system/lib/textfield.lua"]),
    ("browser", "Browser", "4.2.1", "", "netlib,htmllib,textlib", ["system/programs/browser.lua"]),
    ("updater", "Update Center", "2.0.1", "", "netlib,textlib",
        ["system/lib/updater.lua", "system/programs/updatecenter.lua"]),
    ("fixpaint", "FixPaint", "1.4.0", "", "textlib", ["system/programs/fixpaint.lua"]),
    ("devmgr", "Device Manager", "1.0.0", "", "", ["system/programs/devmgr.lua"]),
    ("explorer", "Explorer", "4.3.0", "", "", ["system/programs/explorer.lua"]),
    ("settings", "Settings", "4.3.0", "", "", ["system/programs/settings.lua"]),
    ("calculator", "Calculator", "4.0.1", "", "", ["system/programs/calculator.lua"]),
    ("notepad", "Notepad", "4.0.1", "", "", ["system/programs/notepad.lua"]),
    ("terminal", "Terminal", "4.0.1", "", "", ["system/programs/terminal.lua"]),
    ("mycomputer", "My Computer", "4.0.1", "", "", ["system/programs/mycomputer.lua"]),
]

CHANGELOG = [
    ("4.3.4", "FixPaint: зсув курсора +1 колонка / +2 пікселі вниз за замовчуванням, автокалібрування в режимі клітинок"),
    ("4.3.3", "FixPaint: налаштовуваний зсув курсора (за замовчуванням +1 вправо, +1 вниз), діалог Курсор"),
    ("4.3.2", "FixPaint: курсор без зсуву (режим клітинок за замовчуванням, точний режим з калібруванням)"),
    ("4.3.1", "Курсор: точне визначення режиму миші у FixPaint; текстовий курсор (каретка) у полях введення"),
    ("4.3.0", "Нові програми: FixPaint, Device Manager"),
    ("4.3.0", "Update Center: версії програм, резервні копії, відкат"),
    ("4.2.0", "Browser: HTTPS, редіректи, посилання, пошук, Reader"),
]

RAW = "--raw" in sys.argv
TEXT_EXT = (".lua", ".lang", ".txt", ".md", ".cfg")


def target_of(path):
    if path == "boot/init.lua":
        return "/init.lua"
    return "/" + path


def read(path):
    with open(os.path.join(ROOT, path), "rb") as f:
        data = f.read()
    # Нормалізуємо лише ТЕКСТОВІ файли. Двійкові (PNG містить \r\n у підписі!)
    # чіпати не можна - інакше розмір не збігається з тим, що віддає GitHub.
    if not RAW and path.lower().endswith(TEXT_EXT):
        data = data.replace(b"\r\n", b"\n")
    return data


def main():
    lines = ["manifest=1", "os=" + OS_VERSION, "repo=FixlutGames21/FixOS", "branch=main"]
    seen = set()
    for cid, name, ver, flags, req, patterns in COMPONENTS:
        lines.append("|".join(["component", cid, name, ver, flags, req]))
        files = []
        for pat in patterns:
            matches = sorted(glob.glob(os.path.join(ROOT, pat)))
            if not matches:
                sys.exit("Немає файлів за шаблоном: " + pat)
            for m in matches:
                files.append(os.path.relpath(m, ROOT).replace(os.sep, "/"))
        for path in files:
            if path in seen:
                sys.exit("Файл у двох компонентах: " + path)
            seen.add(path)
            data = read(path)
            lines.append("|".join(["file", cid, path, target_of(path), str(len(data)),
                                    "%08x" % (zlib.adler32(data) & 0xFFFFFFFF)]))
    for ver, text in CHANGELOG:
        lines.append("|".join(["log", ver, text]))
    out = "\n".join(lines) + "\n"
    with open(os.path.join(ROOT, "manifest.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write(out)
    print("manifest.txt: %d компонентів, %d файлів" % (len(COMPONENTS), len(seen)))

    # попередження про файли, яких немає в маніфесті
    ignore = {"manifest.txt", "installer.lua", "README.md", ".gitattributes", "boot/Text.txt"}
    for dirpath, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in (".git", "tools", "__pycache__")]
        for fn in files:
            rel = os.path.relpath(os.path.join(dirpath, fn), ROOT).replace(os.sep, "/")
            if rel not in seen and rel not in ignore:
                print("УВАГА: файл не входить у жоден компонент:", rel)


if __name__ == "__main__":
    main()
