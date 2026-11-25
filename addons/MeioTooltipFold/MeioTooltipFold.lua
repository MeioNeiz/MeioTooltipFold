-- MeioTooltipFold: folds other addons' tooltip lines into Blizzard's own.
--   Pawn: its score and upgrade % move beside the stat line, the scale line hides (Shift
--     shows it)
--   ForeverGear, GearQuest: their score, gain and rank join Pawn's beside the stat line
--   RestedXP: "Item used in guide" lines merge into as few as fit, each guide once
--   Meionomics: its verdict rows move up under Sell Price
--   Leveling BiS: its verdict as a plain line in place of its own block (adds lines, so it is
--     a post-call, not a fold)
--   Hidden lines: any line containing a text you chose (/tooltipfold hide), Shift shows them
-- Runs on every Show: Blizzard shows the tooltip after all TooltipDataProcessor post-calls,
-- and Pawn shows it again after adding its trainer line. Each fold must be idempotent: once
-- applied, the line it looks for no longer matches.

local DEFAULTS = { pawn = true, fg = true, gq = true, rxp = true, meio = true, bis = true }
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
  local to, moved = 1, false
  for from = 1, n do
    local fl, fr = line(from)
    if not Empty(fl, fr) then
      if from ~= to then
        local tl, tr = line(to)
        Put(tl, tr, Grab(fl, fr))
        Hide(fl, fr)
        moved = true
      end
      to = to + 1
    end
  end
  return moved
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

-- Each fold's verdict goes on the right of one line; later folds in the same pass join it,
-- so Pawn, ForeverGear and GearQuest read as one line, a grey bar between them
local placed
local UpgradeTarget
local JOIN = "  |cff808080|||r  "
local WHITE_TEXT = "|cffffffff%s|r"

local function Place(tip, line, before, text)
  local target = placed or UpgradeTarget(tip, line, before)
  if not target then return false end
  if target == placed then
    target:SetText(target:GetText() .. JOIN .. text)
  else
    SetRight(target, text, HIGHLIGHT_FONT_COLOR)
  end
  placed = target
  return true
end

------------------------------------------------------------------------------ Pawn
-- PawnForever adds `|cff33ff99<scale>|r` | `<score>  |cff40ff40<gain>[ with <partner>]|r`
local PAWN_LEFT = "^|cff33ff99(.-)|r$"

-- Where the upgrade goes: the weapon's DPS line, the armour line, else the last stat line,
-- else the name line
function UpgradeTarget(tip, line, before)
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
  if IsShiftKeyDown() then return end
  for i = 2, n do
    local left, right = line(i)
    local scale = Readable(left:GetText()) and left:GetText():match(PAWN_LEFT)
    local value = scale and right and Readable(right:GetText()) and right:GetText()
    if value then
      local score = value:match("^(%S+)")
      local gain = value:match("|cff40ff40(.-)|r")
      if gain then gain = gain:match("^(.-) with .+$") or gain end
      Hide(left, right)
      local verdict = WHITE_TEXT:format(score)
      if gain then
        verdict = verdict .. " " .. GREEN_FONT_COLOR:WrapTextInColorCode(gain)
      end
      Place(tip, line, i, verdict)
      return true
    end
  end
end

------------------------------------------------------------------------------ ForeverGear
-- `|cff66ccffUpgrade score <n>|r` then ` <colour>(<+-d> vs equipped)|r`, ` (equipped)`,
-- ` |cffff4444(you can't use it)|r` or a grey tie. An item you can't use gets no place.
local FG_LEFT = "^|cff66ccffUpgrade score ([^|]+)|r ?(.*)$"
local FG_GAIN = { ["33ff33"] = GREEN_FONT_COLOR, ["ff4444"] = RED_FONT_COLOR }

local function FoldFG(tip, line, n)
  if IsShiftKeyDown() then return end
  for i = 2, n do
    local left, right = line(i)
    local text = left:GetText()
    local score, trail
    if Readable(text) then score, trail = text:match(FG_LEFT) end
    if score then
      if not trail:find("can't use", 1, true) then
        local hex, d = trail:match("^|cff(%x+)%(([%+%-][%d%.]+) vs equipped%)|r$")
        local color = hex and FG_GAIN[hex:lower()]
        local verdict = WHITE_TEXT:format(score)
        if color then
          verdict = verdict .. " " .. color:WrapTextInColorCode((d:gsub("%.0$", "")))
        end
        if not Place(tip, line, i, verdict) then return end
      end
      Hide(left, right)
      return true
    end
  end
end

------------------------------------------------------------------------------ GearQuest
-- A blank line, maybe its enchant lines, `|cffffd100Rank #<n> for your level[ <pair>]|r`
-- then `  |cffffffff<index>|r[  <arrow> |cff00ff00+<d>|r]`, maybe a set note, then other
-- specs' ranks; the note and ranks are `|cffd9bf73...|r` lines
local GQ_LEFT = "^|cffffd100Rank #(%d+) for your level.-|r(.*)$"
local GQ_AFTER = "^|cffd9bf73.*|r$"

local function FoldGQ(tip, line, n)
  if IsShiftKeyDown() then return end
  for i = 2, n do
    local left, right = line(i)
    local text = left:GetText()
    local rank, trail
    if Readable(text) then rank, trail = text:match(GQ_LEFT) end
    if rank then
      local up, down = trail:match("|cff00ff00(%+%d+)|r"), trail:match("|cffff4040(%-%d+)|r")
      local index = trail:match("|cffffffff([%d%.]+)|r")
      local verdict = "|cffffd100#" .. rank .. "|r"
      if index then verdict = verdict .. " " .. WHITE_TEXT:format(index) end
      if up then verdict = verdict .. " " .. GREEN_FONT_COLOR:WrapTextInColorCode(up) end
      if down then verdict = verdict .. " " .. RED_FONT_COLOR:WrapTextInColorCode(down) end
      if not Place(tip, line, i, verdict) then return end
      Hide(left, right)
      local above = line(i - 1):GetText()
      if Readable(above) and above == " " then Hide(line(i - 1)) end
      for j = i + 1, n do
        local l, r = line(j)
        local t = l:GetText()
        if not (Readable(t) and t:find(GQ_AFTER)) then break end
        Hide(l, r)
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
local RXP_LEAD = "Used in guide: "
-- guides join a row up to this many characters, so many guides don't widen the tooltip
local RXP_ROW = 46

local function FoldRXP(tip, line, n)
  if IsShiftKeyDown() then return end
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
      local out, seen = { RXP_LEAD }, {}
      for _, j in ipairs(rows) do
        local guide = line(j):GetText():gsub("^" .. RXP_PREFIX:gsub("\n", "%%c"), "")
          :gsub("^|T.-|t", "")
        if not seen[guide] then
          seen[guide] = true
          local row = out[#out]
          if row == RXP_LEAD then
            out[#out] = row .. guide
          elseif #row + 2 + #guide <= RXP_ROW then
            out[#out] = row .. ", " .. guide
          else
            out[#out] = row .. ","
            out[#out + 1] = guide
          end
        end
      end
      for _, j in ipairs(rows) do Hide(line(j)) end
      for k, row in ipairs(out) do
        if row ~= RXP_LEAD then
          line(rows[k]):SetText((k == 1 and RXP_ICON .. " " or "") .. row)
        end
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

------------------------------------------------------------------------------ Leveling BiS
-- Forever Leveling BiS's verdict as lines of the game's tooltip, in place of its block
-- (patch 64: API.GetVerdicts, API.blockOff). Plain: one line, the main spec's standing in
-- My gear's tier colours (item quality colours), its gain or loss on the right.
-- Shift: each spec's gain and score, and what it replaces. Its own window keeps its block.
local BIS_ICON = "|TInterface\\AddOns\\ForeverLevelingBiS\\Media\\Icon:0|t "
local BIS_UPGRADE = 0.05 -- FLBiS's UPGRADE: the least gain it calls one
local BIS, EPIC, RARE, POOR = { 255, 128, 0 }, { 163, 53, 238 }, { 0, 112, 221 }, { 157, 157, 157 }
local WHITE, GREEN, RED = { 255, 255, 255 }, { 25, 255, 25 }, { 255, 32, 32 }

local function C(c, text)
  return ("|cff%02x%02x%02x%s|r"):format(c[1], c[2], c[3], text)
end

local function Tier(ratio)
  return (ratio >= 0.97 and BIS) or (ratio > 0.85 and EPIC) or (ratio > 0.5 and RARE) or POOR
end

local function Standing(v)
  if v.unlock then
    if v.laterBest then return C(BIS, ("Best in slot at %d"):format(v.unlock)) end
    if not v.laterRatio then return nil end
    return C(Tier(v.laterRatio), ("%d%% of best at %d, #%d %s"):format(
      math.floor(v.laterRatio * 100), v.unlock, v.laterRank, v.laterLabel))
  end
  if v.best then return C(BIS, "Best in slot") end
  if not v.ratio then return nil end
  local text = ("%d%% of best"):format(math.floor(v.ratio * 100))
  if v.rank then text = text .. (", #%d %s"):format(v.rank, v.slotLabel) end
  return C(Tier(v.ratio), text)
end

-- "+8% upgrade" (the share of what it replaces), "+6.1" without one; `all` adds losses
local function Gain(v, all)
  if v.loading or not v.delta then return nil end
  if v.empty then return C(GREEN, "fills empty slot") end
  local d = v.delta
  local pct = v.base and v.base > 0 and d / v.base * 100
  local num = ("%+.1f"):format(d)
  if pct and math.abs(pct) >= 1 and math.abs(pct) < 1000 then
    num = ("%+d%%"):format(pct < 0 and math.ceil(pct - 0.5) or math.floor(pct + 0.5))
  end
  if d >= BIS_UPGRADE then return C(GREEN, num .. " upgrade") end
  if not all then return nil end
  if d <= -BIS_UPGRADE then return C(RED, num .. " downgrade") end
  return C(WHITE, "no change")
end

local function Score(v)
  return C(WHITE, ("%.1f"):format(v.score or 0))
end

local function SpecRight(v)
  if v.reason then return C(RED, v.reason) end
  local lead
  if v.unlock then
    lead = C(RED, ("level %d"):format(v.unlock))
  elseif v.worn then
    lead = C(WHITE, v.have)
  else
    lead = Gain(v, true)
  end
  return lead and (lead .. "  " .. Score(v)) or Score(v)
end

local function OwnWindow(frame)
  while frame do
    if frame.addsBlock then return true end
    local name = frame.GetName and frame:GetName()
    if type(name) == "string" and name:find("^ForeverLevelingBiS") then return true end
    frame = frame.GetParent and frame:GetParent()
  end
end

local function DisplayedLink(tip)
  local link
  if TooltipUtil and TooltipUtil.GetDisplayedItem then
    link = select(2, TooltipUtil.GetDisplayedItem(tip))
  end
  if not link and tip.GetItem then link = select(2, tip:GetItem()) end
  return Readable(link) and link or nil
end

local function AddBis(tip)
  local api = ForeverLevelingBiS_API
  if not (db.bis and api and api.GetVerdicts) then return end
  if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end
  if tip:IsForbidden() or OwnWindow(tip:GetOwner()) then return end
  local link = DisplayedLink(tip)
  if not link then return end
  local held = api.ShowsWorn and api.ShowsWorn(tip, link)
  local main, offs = api.GetVerdicts(link, held)
  if not main or main.cant then return end
  local shift = IsShiftKeyDown()
  local standing = not main.reason and Standing(main)
  -- losses show without Shift too: a loot roll needs no for an answer as much as yes
  local gain = not main.reason and not main.worn and Gain(main, true)
  local verdict = not main.reason and main.score and Score(main)
  if gain then verdict = verdict and (verdict .. "  " .. gain) or gain end
  if standing or verdict or shift then
    local left = BIS_ICON .. (standing or C(WHITE, "Leveling BiS"))
    if verdict then tip:AddDoubleLine(left, verdict) else tip:AddLine(left) end
  end
  if not shift then
    -- one hint per tooltip across our addons (meioShiftHint, cleared with the tooltip)
    if (standing or verdict) and not tip.meioShiftHint then
      tip.meioShiftHint = true
      tip:AddLine("|cff999999Shift: more|r")
    end
    return
  end
  -- the main spec's line: "<spec>: replaces <worn>" | "<score> vs <worn's score>"
  local what, score = nil, Score(main)
  if main.reason then
    what, score = C(RED, main.reason), nil
  elseif main.worn then
    what = main.have
  elseif main.empty then
    what = "empty slot"
  elseif main.bothHands then
    what = "replaces both hands"
  elseif main.vs then
    what = "replaces " .. main.vs
  end
  if what and score and main.base and not main.worn then
    score = score .. C(WHITE, (" vs %.1f"):format(main.base))
  end
  local spec = main.label or "Score"
  local left = what and ("%s: %s"):format(spec, what) or spec
  if score then
    tip:AddDoubleLine(left, score, 1, 1, 1)
  else
    tip:AddLine(left, 1, 1, 1)
  end
  for _, o in ipairs(offs) do tip:AddDoubleLine(o.label, SpecRight(o), 1, 1, 1) end
end

local function SafeBis(tip)
  local ok, err = pcall(AddBis, tip)
  if not ok then geterrorhandler()(err) end
end

local function BlockOff()
  local api = ForeverLevelingBiS_API
  if api and api.GetVerdicts then api.blockOff = db.bis end
end

------------------------------------------------------------------------------ hidden lines
-- db.hide: lower-case texts; a line whose plain text (no colours, icons) contains one hides
local function Bare(text)
  if not Readable(text) then return nil end
  local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    :gsub("|A.-|a", ""):gsub("\n", " ")
  return strtrim(plain)
end

local function Hidden(text)
  local plain = Bare(text)
  if not plain or plain == "" then return false end
  plain = plain:lower()
  for _, h in ipairs(db.hide) do
    if plain:find(h, 1, true) then return true end
  end
  return false
end

local function HideChosen(tip, line, n)
  if not db.hide or #db.hide == 0 or IsShiftKeyDown() then return end
  local changed
  for i = 2, n do
    local left, right = line(i)
    if Hidden(left:GetText()) or (right and right:IsShown() and Hidden(right:GetText())) then
      Hide(left, right)
      changed = true
    end
  end
  return changed
end

------------------------------------------------------------------------------ wiring
local busy = false
local emptied = setmetatable({}, { __mode = "k" })
local function Fold(tip)
  if busy or tip:IsForbidden() then return end
  local n = tip:NumLines()
  if n < 2 then return end
  local line = Lines(tip)
  placed = nil
  local changed = db.meio and FoldBest(tip, line, n)
  changed = db.pawn and FoldPawn(tip, line, n) or changed
  changed = db.fg and FoldFG(tip, line, n) or changed
  changed = db.gq and FoldGQ(tip, line, n) or changed
  changed = db.rxp and FoldRXP(tip, line, n) or changed
  changed = HideChosen(tip, line, n) or changed
  if changed then emptied[tip] = true end
  -- lines added on a later Show (Meionomics' Shift ledger) land below the emptied ones
  local moved = emptied[tip] and Compact(line, n)
  if changed or moved then
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
      pcall(tip.HookScript, tip, "OnTooltipCleared", function()
        folded[tip], emptied[tip], tip.meioShiftHint = nil, nil, nil
      end)
    end
  end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, SafeBis)
  end
  BlockOff()
end
------------------------------------------------------------------------------ settings
-- Chat toggles and the Settings panel (Esc > Options > AddOns > MeioTooltipFold) share these
-- words and both write MeioTooltipFoldDB
local FOLDS = {
  { key = "pawn", label = "Pawn on stat line",
    tip = "Pawn's score and upgrade % go on the right of the damage, armour or last stat line"
      .. " and its scale line hides (Shift shows it). Off: Pawn's lines as Pawn adds them." },
  { key = "fg", label = "ForeverGear gain",
    tip = "ForeverGear's score and gain over what you wear join the right of the damage, armour"
      .. " or last stat line; its line hides (Shift shows it). Off: ForeverGear's own line." },
  { key = "gq", label = "GearQuest rank",
    tip = "GearQuest's rank for your level, score and gain (\"#3 72 +12\") join the right of the"
      .. " damage, armour or last stat line; its line, the gap above it and the other specs'"
      .. " ranks hide (Shift shows them). Off: GearQuest's own lines." },
  { key = "rxp", label = "RestedXP merged",
    tip = "RestedXP's \"Item used in guide\" lines merge into one (two when there are many),"
      .. " every guide named once (Shift shows RestedXP's own lines). Off: their own lines." },
  { key = "meio", label = "Meionomics up",
    tip = "Meionomics' price lines move up to just under Sell Price when another addon's lines"
      .. " landed between them. Off: they stay where they were added." },
  { key = "bis", label = "BiS as one line",
    tip = "Forever Leveling BiS's verdict as one plain line (standing, score, and the upgrade"
      .. " or downgrade) in place of its boxed block. Shift adds each spec's score and what it"
      .. " replaces. Off: its own block." },
}

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffb090ffMeioTooltipFold:|r " .. msg)
end

local function OnOff(on)
  return on and "|cff80ff80on|r" or "|cffff8080off|r"
end

local function Cmd(text)
  return "|cffffd100" .. text .. "|r"
end

local function Help()
  Print("folds other addons' tooltip lines into Blizzard's own. Hold Shift for the detail.")
  local add = DEFAULT_CHAT_FRAME
  for _, f in ipairs(FOLDS) do
    add:AddMessage(("  %s - %s (now %s)"):format(Cmd("/tooltipfold " .. f.key .. " on||off"),
      f.label, OnOff(db[f.key])))
  end
  add:AddMessage(("  %s - hide lines containing a text; alone, over an item: its lines to"
    .. " pick from; %s shows one again; Shift shows them all"):format(
    Cmd("/tooltipfold hide <text||n>"), Cmd("/tooltipfold unhide <n>")))
  add:AddMessage(("  %s - default settings, nothing hidden"):format(Cmd("/tooltipfold reset")))
  add:AddMessage(("  Settings: Esc > Options > AddOns > MeioTooltipFold (%s)")
    :format(Cmd("/tooltipfold settings")))
end

-- the hovered tooltip's lines from the last /tooltipfold hide, for /tooltipfold hide <n>
local listed = {}

local function ListTooltip()
  if not GameTooltip:IsShown() or GameTooltip:IsForbidden() then return false end
  local line = Lines(GameTooltip)
  wipe(listed)
  for i = 2, GameTooltip:NumLines() do
    local text = Bare(line(i):GetText())
    if text and text ~= "" then listed[#listed + 1] = text end
  end
  if #listed == 0 then return false end
  Print(("this tooltip's lines (%s hides one):"):format(Cmd("/tooltipfold hide <n>")))
  for i, text in ipairs(listed) do DEFAULT_CHAT_FRAME:AddMessage(("  %d. %s"):format(i, text)) end
  return true
end

local function ListHidden()
  if #db.hide == 0 then
    Print(("nothing hidden. Hover an item and type %s to pick a line."):format(
      Cmd("/tooltipfold hide")))
    return
  end
  Print("hiding lines that contain (Shift shows them):")
  for i, text in ipairs(db.hide) do DEFAULT_CHAT_FRAME:AddMessage(("  %d. %s"):format(i, text)) end
  DEFAULT_CHAT_FRAME:AddMessage(("  %s shows one again, %s all"):format(
    Cmd("/tooltipfold unhide <n>"), Cmd("/tooltipfold unhide all")))
end

local function HideText(arg)
  if arg == "" then
    if not ListTooltip() then ListHidden() end
    return
  end
  local text = strtrim((tonumber(arg) and listed[tonumber(arg)] or arg):lower())
  if tContains(db.hide, text) then
    Print(("already hiding \"%s\""):format(text))
    return
  end
  table.insert(db.hide, text)
  Print(("hiding lines that contain \"%s\" (Shift shows them; %s to undo)"):format(text,
    Cmd("/tooltipfold unhide " .. #db.hide)))
end

local function Unhide(arg)
  if arg == "all" then
    wipe(db.hide)
    Print("nothing hidden")
    return
  end
  local i = tonumber(arg)
  if not (i and db.hide[i]) then
    for j, text in ipairs(db.hide) do
      if text == arg then i = j end
    end
  end
  if i and db.hide[i] then
    Print(("showing lines with \"%s\" again"):format(table.remove(db.hide, i)))
  else
    ListHidden()
  end
end

local category

local function Register()
  if category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
  local layout
  category, layout = Settings.RegisterVerticalLayoutCategory("MeioTooltipFold")
  if layout and CreateSettingsListSectionHeaderInitializer then
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Item tooltips",
      "Which addons' lines are folded into Blizzard's own. Hold Shift on a tooltip for the"
        .. " detail."))
  end
  for _, f in ipairs(FOLDS) do
    local setting = Settings.RegisterAddOnSetting(category, "TOOLTIPFOLD_" .. f.key:upper(),
      f.key, db, Settings.VarType.Boolean, f.label, DEFAULTS[f.key])
    if f.key == "bis" then setting:SetValueChangedCallback(BlockOff) end
    Settings.CreateCheckbox(category, setting, f.tip)
  end
  if layout and CreateSettingsListSectionHeaderInitializer then
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Hidden lines",
      "Hide any line you never read: hover an item, type /tooltipfold hide and pick its"
        .. " number, or /tooltipfold hide <text> for every line containing that text. Shift"
        .. " shows them."))
  end
  if layout and CreateSettingsButtonInitializer then
    layout:AddInitializer(CreateSettingsButtonInitializer("Hidden lines", "List in chat",
      ListHidden, "Every text hidden, with /tooltipfold unhide to show one again.", true))
  end
  Settings.RegisterAddOnCategory(category)
end

local function OpenSettings()
  if category then
    Settings.OpenToCategory(category:GetID())
  else
    Help()
  end
end
MeioTooltipFold_OpenSettings = OpenSettings

local BY_KEY = {}
for _, f in ipairs(FOLDS) do BY_KEY[f.key] = f end

SLASH_MEIOTOOLTIPFOLD1 = "/tooltipfold"
SlashCmdList.MEIOTOOLTIPFOLD = function(msg)
  local key, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
  local f = BY_KEY[key]
  if key == "" or key == "settings" or key == "options" then
    OpenSettings()
  elseif key == "help" or key == "?" then
    Help()
  elseif f and (arg == "on" or arg == "off" or arg == "") then
    if arg == "" then db[key] = not db[key] else db[key] = arg == "on" end
    BlockOff()
    Print(("%s %s"):format(f.label, OnOff(db[key])))
  elseif key == "hide" then
    HideText(arg)
  elseif key == "unhide" then
    Unhide(arg)
  elseif key == "reset" then
    wipe(db)
    for k, v in pairs(DEFAULTS) do db[k] = v end
    db.hide = {}
    BlockOff()
    Print("default settings, nothing hidden")
  else
    Print(("unknown command \"%s\""):format(strtrim(msg or "")))
    Help()
  end
end

local function Load()
  MeioTooltipFoldDB = type(MeioTooltipFoldDB) == "table" and MeioTooltipFoldDB or {}
  db = MeioTooltipFoldDB
  for k, v in pairs(DEFAULTS) do
    if db[k] == nil then db[k] = v end
  end
  if type(db.hide) ~= "table" then db.hide = {} end
end

local function Login()
  Install()
  local ok, err = pcall(Register)
  if not ok then geterrorhandler()(err) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" then
    if name == "MeioTooltipFold" then Load() end
  else
    Login()
  end
end)
if IsLoggedIn() then
  Load()
  Login()
  f:UnregisterEvent("PLAYER_LOGIN")
end
