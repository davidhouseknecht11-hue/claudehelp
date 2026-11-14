# Installing the disaster + shop upgrade

## Fast way (one file)
1. Import the models: **File > Import 3D > `LobbyKit.glb`**, move the new LobbyKit to ServerStorage and delete the old one.
2. Right-click **ServerScriptService > Insert from File… > `TuffUpdate_AllScripts.rbxmx`**.
   That adds a `TuffUpdate` folder holding every script (its scripts stay switched off for now).
3. Open **View > Command Bar**, paste this line, press Enter:

   ```lua
   local s=game:GetService("ServerScriptService") local u=s:FindFirstChild("TuffUpdate") or workspace:FindFirstChild("TuffUpdate") if not u then return warn("No TuffUpdate folder - insert TuffUpdate_AllScripts.rbxmx first. Nothing was changed.") end local sp=game.StarterPlayer local function put(n,p) local new=u:FindFirstChild(n) if not new then return end local o=p:FindFirstChild(n) if o then o:Destroy() end new.Parent=p end put("LobbyUpgrade",s) put("DisasterGameManager",s) put("DrowningSystem",s) put("DisasterConfig",game.ReplicatedStorage.DisasterAssets) put("PetsClient",sp.StarterPlayerScripts) put("UnderwaterFX",sp.StarterPlayerScripts) put("SwimController",sp.StarterCharacterScripts) put("ProgressionServer",s) put("PetService",s) put("DisasterSelectorClient",sp.StarterPlayerScripts) for _,n in ipairs({"LobbyUpgrade","DisasterGameManager","DrowningSystem","ProgressionServer","PetService"}) do s[n].Enabled=true end u:Destroy() print("TuffUpdate installed")
   ```

   It replaces LobbyUpgrade, DisasterGameManager, DrowningSystem, ProgressionServer, PetService, DisasterConfig,
   PetsClient, UnderwaterFX, SwimController and DisasterSelectorClient with the new ones and turns them on.
   Safe to run twice: with no TuffUpdate folder it changes nothing.

   Note: the disaster summons and Robux eggs need developer products. Create them in Creator Hub and paste the
   ids into `ShopItems.NewProducts` (SummonCommon / Rare / Mythic / Transcendent, RobuxEggCommon / Rare / Mythic).
   Optional: upload `stud_tile.png` as an image and paste its id into `ShopItems.StudTexture`.
   The Output window says `TuffUpdate installed` when it worked. Then press Play.

## Step by step

1. In Studio, delete the old `LobbyKit` model and the old `ServerScriptService > LobbyUpgrade`.
2. **File > Import 3D > `LobbyKit.glb`** (it now also holds the shop items, effect pieces and new hazard models).
3. Drag **`LobbyUpgrade.rbxmx`** into `ServerScriptService`. It contains LobbyUpgrade with
   KitLoader, KitAnimator, DisasterFX, ShopUI and ShopItems inside.
4. One line in **`StarterPlayerScripts > PetsClient`** so the Pets tab shows pets hatched from the new shop.
   Easiest: replace the whole script with `scripts_ready_to_paste/PetsClient.lua` (already patched).
   Or by hand: in `setTab`, replace

   ```lua
   if name == "Pets" then
       refreshPets()
   end
   ```

   with

   ```lua
   if name == "Pets" then
       local res = request("State")
       if res.ok then applyState(res) end
       refreshPets()
   end
   ```

5. **Moon Collision (Transcendent disaster)** needs two of the game's own scripts replaced
   (right-click the parent > Insert from File, after deleting the old one):
   - `ReplicatedStorage > DisasterAssets > DisasterConfig` → `DisasterConfig.rbxmx`
     (adds the Transcendent tier and Moon Collision at 1 in 10,000 rounds)
   - `ServerScriptService > DisasterGameManager` → `DisasterGameManager.rbxmx`
     (a 4-line hook so add-on disasters can run; nothing else changed)
   To test it without waiting 10,000 rounds, pick **Moon Collision** in your Admin panel.

## Robux items
Prices on the cards come from `ShopItems` until a real id is set. Then the real Roblox price is shown.
- Existing items (500 / 2,500 coins, Streak Saver, Revive, Server Luck, 2x Coins, VIP): put their ids in `ProgressionConfig`.
- The two new coin packs (6,000 and 15,000 coins): put their ids in `ShopItems.NewProducts`.

## Settings
- `DisasterFX`: `SHOW_INTRO`, `REPLACE_HAZARD_LOOKS`, `WIND_PUSH` (0 = wind is visual only), debris counts, and `PROFILES` (wind / weather / colour per disaster).
- To use your own tornado instead of the Blender one, put it in `ServerStorage > TornadoAssets > Tornado` and LobbyUpgrade leaves it alone.
