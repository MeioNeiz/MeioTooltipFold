# Meio Tooltip Fold

Short item tooltips: the lines other addons pile at the bottom move into Blizzard's own.

![A cloak's tooltip: before, Pawn's upgrade, four RestedXP guide lines and Meionomics' price
at the bottom; with TooltipFold, the upgrade beside the armour, the price under Sell Price and
the guides in one line](docs/before-after.png)

## What it does

Each addon's lines go where they belong, and only when that addon is installed.

- **Pawn**: the upgrade percentage sits beside the weapon's damage, the armour or the last
  stat; its scale line hides
- **RestedXP Guides**: "Item used in guide" becomes one line, each guide named once, only
  guides that start near your level
- **Meionomics**: its price sits right under Sell Price
- Hold **Shift** to see everything as the addons wrote it

Settings: Esc > Options > AddOns > TooltipFold, or `/tooltipfold`.

## Slash commands

- `/tooltipfold`: settings
- `/tooltipfold help`: every command
- `/tooltipfold pawn on`, `rxp on`, `meio on` (or `off`): fold that addon's lines or leave them
- `/tooltipfold bis on|off`: Forever Leveling BiS's verdict as one line (needs a Leveling BiS
  version that lets other addons take over its block; the current one doesn't yet)
- `/tooltipfold near <levels>`: how far above your level a guide may start (default 5)
- `/tooltipfold reset`: back to the defaults

## Install

Use your addon manager (CurseForge, Wago), or unzip a GitHub release into
`World of Warcraft\_forever_\Interface\AddOns` and restart WoW fully.

## Feedback

Bugs and ideas: [GitHub issues](https://github.com/MeioNeiz/TooltipFold/issues)

## More Meio addons

[Meio TrainerCompare](https://www.curseforge.com/wow/addons/trainercompare) | [Meio Next Stop](https://www.curseforge.com/wow/addons/leavebutton) | [Meio AutoRank](https://www.curseforge.com/wow/addons/meio-autorank) | [Meio MeterHover](https://www.curseforge.com/wow/addons/meterhover) | [Meio Map](https://addons.wago.io/addons/meiomap) | [Meio Alts](https://addons.wago.io/addons/meioalts) | [Meio DPS](https://addons.wago.io/addons/meiodps) | [Meio Plates](https://addons.wago.io/addons/meioplates) | [Meio Hub](https://addons.wago.io/addons/meiohub) | [Meio Pets](https://addons.wago.io/addons/meiopets) | [Meio Stats](https://addons.wago.io/addons/meiostats) | [Meio Bags](https://addons.wago.io/addons/meiobags) | [Meio Fixes](https://addons.wago.io/addons/meiofixes) | [Meio Flight Times](https://addons.wago.io/addons/meioflighttimes)

## Licence

[MIT](LICENSE)
