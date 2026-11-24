-- TooltipFold: folds other addons' tooltip lines into Blizzard's own.
--   Pawn: the upgrade % moves beside the stat line, the scale line hides (Shift shows it)
--   RestedXP: "Item used in guide" lines merge into one, deduped, near your level only
--   Meionomics: its verdict rows move up under Sell Price
-- Runs on every Show: Blizzard shows the tooltip after all TooltipDataProcessor post-calls,
-- and Pawn shows it again after adding its trainer line. Each fold must be idempotent: once
-- applied, the line it looks for no longer matches.

local DEFAULTS = { pawn = true, rxp = true, meio = true, near = 5 }
local db = DEFAULTS

local TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }

local function Readable(text)
  return type(text) == "string" and (not canaccessvalue or canaccessvalue(text))
end

local function Lines(tip)
  local name = tip:GetName()
  return function(i) return _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i] end
end

local function Hide(left, right)
  left:SetText(nil)
  if right then
    right:SetText(nil)
    right:Hide()
  end
end

-- Secret text can't even be compared to nil; it is real content, so not blank
local function Blank(text)
  return type(text) ~= "string" or (Readable(text) and text == "")
end

local function Empty(left, right)
  return Blank(left:GetText())
    and Blank(right and right:IsShown() and right:GetText())
end

-- Line state as plain values, so lines can be rotated without reading a half-written one
local function Grab(left, right)
  local s = { font = left:GetFontObject(), text = left:GetText(),
    color = { left:GetTextColor() } }
  if left.CanWordWrap then s.wrap = left:CanWordWrap() end
  if right and right:IsShown() then
    s.rfont, s.rtext = right:GetFontObject(), right:GetText()
    s.rcolor = { right:GetTextColor() }
  end
  return s
end

local function Put(left, right, s)
  left:SetFontObject(s.font)
  left:SetText(s.text)
  left:SetTextColor(unpack(s.color))
  if left.SetWordWrap and s.wrap ~= nil then left:SetWordWrap(s.wrap) end
  if not right then return end
  if s.rtext then
    right:SetFontObject(s.rfont)
    right:SetText(s.rtext)
    right:SetTextColor(unpack(s.rcolor))
    right:Show()
  else
    right:SetText(nil)
    right:Hide()
  end
end

-- Emptied lines may still take a line's height, so the lines below move up over them
local function Compact(line, n)
  for i = 1, n do
    local left, right = line(i)
    if not Readable(left:GetText() or "")
      or (right and not Readable(right:GetText() or "")) then
      return
    end
  end
  local to = 1
  for from = 1, n do
    local fl, fr = line(from)
    if not Empty(fl, fr) then
      if from ~= to then
        local tl, tr = line(to)
        Put(tl, tr, Grab(fl, fr))
        Hide(fl, fr)
      end
      to = to + 1
    end
  end
end

-- Compact leaves emptied lines at the bottom. Whether the client gives them height is
-- unknown, so measure: cut exactly what they span below the last real line (0 if
-- collapsed).
-- Every Show re-sizes the tooltip, so this reruns on each one
local function Trim(tip, line, n)
  local last = n
  while last > 1 and Empty(line(last)) do last = last - 1 end
  if last == n then return end
  local real, bottom = line(last):GetBottom(), line(n):GetBottom()
  if type(real) ~= "number" or type(bottom) ~= "number" then return end
  if canaccessvalue and not (canaccessvalue(real) and canaccessvalue(bottom)) then
    return
  end
  local cut = real - bottom
  if cut > 0.5 then tip:SetHeight(tip:GetHeight() - cut) end
end

local function SetRight(right, text, color)
  right:SetText(text)
  right:SetTextColor(color.r, color.g, color.b)
  right:Show()
end

local function RightFree(right)
  return right
    and not (right:IsShown() and Readable(right:GetText()) and right:GetText() ~= "")
end

------------------------------------------------------------------------------ Pawn
-- PawnForever adds `|cff33ff99<scale>|r` | `<score>  |cff40ff40<gain>[ with <partner>]|r`
local PAWN_LEFT = "^|cff33ff99(.-)|r$"

-- Where the upgrade goes: the weapon's DPS line, the armour line, else the last stat line,
-- else the name line
local function UpgradeTarget(tip, line, before)
  local last
  for i = 2, before - 1 do
    local left, right = line(i)
    local text = left and left:GetText()
    if Readable(text) and RightFree(right) then
      if text:find("damage per second%)$") or text:find("^%d+ Armor$") then return right end
      if text:find("^[%+%-]%d+ %a") then last = right end
    end
  end
  if last then return last end
  local _, right = line(1)
  return RightFree(right) and right or nil
end

local function FoldPawn(tip, line, n)
  for i = 2, n do
    local left, right = line(i)
    local scale = Readable(left:GetText()) and left:GetText():match(PAWN_LEFT)
    local value = scale and right and Readable(right:GetText()) and right:GetText()
    if value then
      local score = value:match("^(%S+)")
      local gain = value:match("|cff40ff40(.-)|r")
      local partner
      if gain then
        gain, partner = gain:match("^(.-) with (.+)$") or gain, gain:match(" with (.+)$")
      end
      if IsShiftKeyDown() then
        left:SetText(scale)
        left:SetTextColor(1, 1, 1)
        right:SetText(partner and ("%s (with %s)"):format(score, partner) or score)
        right:SetTextColor(1, 1, 1)
      else
        Hide(left, right)
      end
      if gain then
        local target = UpgradeTarget(tip, line, i)
        if target then SetRight(target, gain, GREEN_FONT_COLOR) end
      end
      return true
    end
  end
end

------------------------------------------------------------------------------ RestedXP
-- RXP: "Item used in guide:\n<icon><guide>" then "<icon><guide>" per further step, with
-- repeats when one guide has two turn-in steps for the item
local RXP_PREFIX = "Item used in guide:\n"
local RXP_ICON = "|TInterface/GossipFrame/ActiveQuestIcon:0|t"

local function FoldRXP(tip, line, n)
  for i = 2, n do
    local first = line(i)
    local text = first:GetText()
    if Readable(text) and text:sub(1, #RXP_PREFIX) == RXP_PREFIX then
      local rows = { i }
      for j = i + 1, n do
        local t = line(j):GetText()
        if not (Readable(t) and t:sub(1, #RXP_ICON) == RXP_ICON) then break end
        rows[#rows + 1] = j
      end
      local kept, seen = {}, {}
      local maxLevel = UnitLevel("player") + db.near
      for _, j in ipairs(rows) do
        local guide = line(j):GetText():gsub("^" .. RXP_PREFIX:gsub("\n", "%%c"), "")
          :gsub("^|T.-|t", "")
        local from = tonumber(guide:match("^(%d+)"))
        if not seen[guide] and (IsShiftKeyDown() or not from or from <= maxLevel) then
          seen[guide] = true
          kept[#kept + 1] = guide
        end
      end
      for _, j in ipairs(rows) do Hide(line(j)) end
      if #kept > 0 then
        first:SetText(RXP_ICON .. " Used in guide: " .. table.concat(kept, ", "))
      end
      return true
    end
  end
end

------------------------------------------------------------------------------ Meionomics
-- The Best line belongs right under Sell Price, but other addons' lines can land between
-- them when their hooks run before Meionomics'
local SELL_PREFIX = SELL_PRICE .. ":"

local function Plain(text)
  return Readable(text) and text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

-- Meionomics records the verdict rows (T.bestLine..T.bestLast); they carry no fixed text to
-- match since the compact view went icon-only. Without bestLast, moving bestLine alone
-- would split an icon line from its price line, so leave it
local function FindBest(tip, line, n)
  local T = Meionomics and Meionomics.Tooltip
  local first = T and T.bestLine and T.bestLine[tip]
  local last = T and T.bestLast and T.bestLast[tip]
  if not (first and last) or first < 2 or last < first or last > n then return end
  local text = Plain(line(first):GetText())
  if not text or text == "" then return end
  return first, last
end

-- tooltips re-Show without clearing; once moved, bestLine no longer points at the verdict
local folded = setmetatable({}, { __mode = "k" })

local function FoldBest(tip, line, n)
  if folded[tip] then return end
  local first, last = FindBest(tip, line, n)
  if not first then return end
  folded[tip] = true
  local slot
  for i = 2, first - 1 do
    local text = Plain(line(i):GetText() or "")
    if not text then return end
    if text:sub(1, #SELL_PREFIX) == SELL_PREFIX then slot = i + 1 end
  end
  if not slot or slot == first then return end
  local k = last - first + 1
  local states = {}
  for i = slot, last do states[i] = Grab(line(i)) end
  for i = slot, last do
    local left, right = line(i)
    local from = i < slot + k and first + (i - slot) or i - k
    Put(left, right, states[from])
  end
  return true
end

------------------------------------------------------------------------------ wiring
local busy = false
local function Fold(tip)
  if busy or tip:IsForbidden() then return end
  local n = tip:NumLines()
  if n < 2 then return end
  local line = Lines(tip)
  local changed = db.meio and FoldBest(tip, line, n)
  changed = db.pawn and FoldPawn(tip, line, n) or changed
  changed = db.rxp and FoldRXP(tip, line, n) or changed
  if changed then
    Compact(line, n)
    busy = true
    tip:Show()
    busy = false
  end
  Trim(tip, line, n)
end

local function Safe(tip)
  local ok, err = pcall(Fold, tip)
  if not ok then
    busy = false
    geterrorhandler()(err)
  end
end

local function Install()
  for _, name in ipairs(TOOLTIPS) do
    local tip = _G[name]
    if tip then
      hooksecurefunc(tip, "Show", Safe)
      pcall(tip.HookScript, tip, "OnTooltipCleared", function() folded[tip] = nil end)
    end
  end
end
------------------------------------------------------------------------------ settings
local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99TooltipFold|r: " .. msg)
end

local NAMES = { pawn = "Pawn", rxp = "RestedXP", meio = "Meionomics" }
local ORDER = { "pawn", "rxp", "meio" }

local function Status()
  local parts = {}
  for _, k in ipairs(ORDER) do
    parts[#parts + 1] = NAMES[k] .. (db[k] and " on" or " off")
  end
  Print(table.concat(parts, ", ") .. (". RestedXP guides up to %d levels above you.")
    :format(db.near))
  Print("/tooltipfold pawn | rxp | meio on|off, /tooltipfold near <levels>,"
    .. " /tooltipfold reset")
end

SLASH_TOOLTIPFOLD1 = "/tooltipfold"
SlashCmdList.TOOLTIPFOLD = function(msg)
  local key, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
  if NAMES[key] and (arg == "on" or arg == "off") then
    db[key] = arg == "on"
    Print(("%s %s."):format(NAMES[key], arg))
  elseif key == "near" and tonumber(arg) then
    db.near = math.max(0, math.floor(tonumber(arg)))
    Print(("RestedXP guides up to %d levels above you."):format(db.near))
  elseif key == "reset" then
    wipe(db)
    for k, v in pairs(DEFAULTS) do db[k] = v end
    Print("settings reset.")
  else
    Status()
  end
end

local function Load()
  TooltipFoldDB = type(TooltipFoldDB) == "table" and TooltipFoldDB or {}
  db = TooltipFoldDB
  for k, v in pairs(DEFAULTS) do
    if db[k] == nil then db[k] = v end
  end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" then
    if name == "TooltipFold" then Load() end
  else
    Install()
  end
end)
if IsLoggedIn() then
  Load()
  Install()
  f:UnregisterEvent("PLAYER_LOGIN")
end
