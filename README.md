# MyCrafting

**MyCrafting** enhances World of Warcraft's default crafting interface (**WoW Forever**, **Classic Era**, **TBC**, and modern clients) directly in-place, without replacing or hiding the default Blizzard window. It adds a docked side panel and buttons inspired by **Skillet** and **MyProfs**.

---

## ✨ Features Directly Enhancing the Default UI

### 1. Docked Side Panel (Attached to TradeSkillFrame & CraftFrame)
* Opens seamlessly right beside the default profession window.
* Can be collapsed or expanded anytime using the `(X)` close button on the panel or the `>>` / `<<` side tab on the default window.
* Contains two tabs:
  * **Craft Queue**: Live view of all queued crafts with counts, plus **`[Craft Queue]`** (automated sequential casting engine), **`[Pause]`**, and **`[Clear]`**.
  * **Shopping List**: Consolidated missing materials needed for all queued recipes, comparing requirements against your bags and bank. Includes **`[Share Chat]`** and **`[Buy Vendor]`**.

### 2. Injected `[+ Queue]` Button
* Injected directly into the default `TradeSkillFrame` / `CraftFrame` right next to the Create Button.
* Reads the recipe you currently have selected in the default UI and the quantity in the edit box, queuing it with one click.

### 3. Sub-Recipe / Reagent Navigation (Skillet style)
* Hovering over any reagent button in the default UI shows your bag count, bank count, and vendor availability.
* If you also know the recipe to craft that reagent (e.g. Iron Bar for an Iron Breastplate, or Shadow Oil), the tooltip shows `|cff33ff99Click to jump to recipe|r`.
* Clicking the reagent in the default window **instantly jumps to and selects that recipe**!

### 4. Smart Shopping List & Vendor Automation
* **Bank Inventory Tracking**: Automatically caches your bank contents when speaking to a banker.
* **Vendor Database**: Identifies reagents sold by NPCs and calculates exact costs.
* **1-Click Vendor Purchase**: Press `[Buy Vendor]` at any merchant to automatically purchase missing shopping list reagents sold by that merchant.
* **Optional Auto-Buy**: Enable auto-purchasing to buy needed vendor mats automatically when opening a merchant.

---

## ⌨️ Slash Commands

| Command | Description |
|---|---|
| `/mc` or `/mycrafting` | Toggle the MyCrafting side panel on the active profession window |
| `/mc queue` | Display current queue in chat |
| `/mc shop` | Print shopping list of missing mats to chat |
| `/mc clear` | Clear all queued crafts |
| `/mc autobuy [on\|off]` | Toggle auto-purchasing vendor reagents at merchants |

---

## 🛠️ File Structure

* `MyCrafting.toc`: Addon metadata and load order.
* `Compat.lua`: Cross-version API abstraction layer supporting `C_TradeSkillUI`, `C_Container`, `C_Item`, and legacy `GetTradeSkill*` / `GetCraft*` APIs.
* `VendorDB.lua`: Vendor reagent pricing database, merchant scanner, and purchasing automation.
* `Queue.lua`: Queue storage, shopping list aggregator, and sequential automated craft engine.
* `UI.lua`: Side panel dock, `+ Queue` button injection, and reagent tooltip/click hooks.
* `Core.lua`: Addon lifecycle, events, bank caching, and slash commands.
