-- ==============================================
-- FixOS 3.0 - Icon System with Image Support
-- Підтримка іконок 64x64 з масштабуванням
-- ==============================================

local icons = {}

-- Простий ASCII art для іконок (використовується як fallback)
icons.ascii = {
  computer = {
    "╔══════╗",
    "║ [PC] ║",
    "║ ████ ║",
    "╚══════╝"
  },
  calculator = {
    "┌──────┐",
    "│ 7890 │",
    "│ ╬═╬═ │",
    "└──────┘"
  },
  notepad = {
    "┌──────┐",
    "│ ≡≡≡≡ │",
    "│ ≡≡≡≡ │",
    "└──────┘"
  },
  settings = {
    "  ╔═╗  ",
    "╔═╬═╬═╗",
    "╚═╬═╬═╝",
    "  ╚═╝  "
  },
  terminal = {
    "┌──────┐",
    "│ >_   │",
    "│ █    │",
    "└──────┘"
  },
  folder = {
    " ╔════╗ ",
    "╔╝DIR ╚╗",
    "║ FILE ║",
    "╚══════╝"
  },
  file = {
    "┌──────┐",
    "│ TXT  │",
    "│      │",
    "└──────┘"
  }
}

-- Функція для малювання ASCII іконки
function icons.drawAscii(gpu, iconName, x, y, color)
  local icon = icons.ascii[iconName] or icons.ascii.file
  color = color or 0xFFFFFF
  gpu.setForeground(color)
  
  for i, line in ipairs(icon) do
    local lineX = x + math.floor((8 - #line) / 2)
    gpu.set(lineX, y + i - 1, line)
  end
end

-- Функція для малювання іконки з масштабуванням
-- targetW, targetH - розмір куди малювати (наприклад 8x4 для десктопу)
function icons.draw(gpu, iconName, x, y, targetW, targetH, color)
  -- Поки що використовуємо ASCII
  -- В майбутньому тут можна додати растрові іконки
  icons.drawAscii(gpu, iconName, x, y, color)
end

-- Логотип FixOS
icons.logo = {
  "███████╗██╗██╗  ██╗ ██████╗ ███████╗",
  "██╔════╝██║╚██╗██╔╝██╔═══██╗██╔════╝",
  "█████╗  ██║ ╚███╔╝ ██║   ██║███████╗",
  "██╔══╝  ██║ ██╔██╗ ██║   ██║╚════██║",
  "██║     ██║██╔╝ ██╗╚██████╔╝███████║",
  "╚═╝     ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝"
}

-- Маленький логотип
icons.smallLogo = {
  "╔═══════╗",
  "║ FixOS ║",
  "║  3.0  ║",
  "╚═══════╝"
}

return icons
