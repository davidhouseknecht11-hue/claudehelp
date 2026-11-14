"""Packs the three Luau scripts into LobbyUpgrade.rbxmx (drag that file into Roblox Studio).

Run after blender_lobby_kit.py (it needs palette.lua):   python make_install_file.py
"""
import os
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))


def read(*p):
    with open(os.path.join(HERE, *p), encoding="utf8") as fh:
        return fh.read()


palette = read("palette.lua").rstrip("\n")
sources = {
    "LobbyUpgrade": read("src", "LobbyUpgrade.lua"),
    "KitLoader": read("src", "KitLoader.lua").replace("--@PALETTE@", palette),
    "KitAnimator": read("src", "KitAnimator.lua"),
    "DisasterFX": read("src", "DisasterFX.lua"),
    "ShopUI": read("src", "ShopUI.lua"),
    "ShopItems": read("src", "ShopItems.lua"),
    "MoonCollision": read("src", "MoonCollision.lua"),
    "MoonFX": read("src", "MoonFX.lua"),
}
assert "--@PALETTE@" not in sources["KitLoader"]


def item(cls, name, source, run_context=None, children="", disabled=False):
    assert "]]>" not in source
    props = '<string name="Name">%s</string>' % escape(name)
    if cls == "Script":
        props += '<bool name="Disabled">%s</bool><token name="RunContext">%d</token>' % ("true" if disabled else "false", run_context or 0)
    props += '<ProtectedString name="Source"><![CDATA[%s]]></ProtectedString>' % source
    return '<Item class="%s" referent="RBX_%s"><Properties>%s</Properties>%s</Item>' % (cls, name, props, children)


children = item("ModuleScript", "KitLoader", sources["KitLoader"]) + \
    item("Script", "KitAnimator", sources["KitAnimator"], run_context=2) + \
    item("Script", "DisasterFX", sources["DisasterFX"], run_context=2) + \
    item("Script", "ShopUI", sources["ShopUI"], run_context=2) + \
    item("ModuleScript", "ShopItems", sources["ShopItems"]) + \
    item("ModuleScript", "MoonCollision", sources["MoonCollision"]) + \
    item("Script", "MoonFX", sources["MoonFX"], run_context=2)   # run_context 2 = Client
xml = '<roblox xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="4">' + \
    item("Script", "LobbyUpgrade", sources["LobbyUpgrade"], run_context=0, children=children) + "</roblox>\n"

with open(os.path.join(HERE, "LobbyUpgrade.rbxmx"), "w", encoding="utf8", newline="\n") as fh:
    fh.write(xml)

# plain copies with the palette filled in, for reading / pasting by hand
os.makedirs(os.path.join(HERE, "scripts_ready_to_paste"), exist_ok=True)
for name, src in sources.items():
    with open(os.path.join(HERE, "scripts_ready_to_paste", name + ".lua"), "w", encoding="utf8", newline="\n") as fh:
        fh.write(src)
print("wrote LobbyUpgrade.rbxmx", len(xml), "bytes")

# Patched copies of the game's own scripts (replace the originals with Insert from File)
patched = ""
for name, cls in (("PetsClient", "LocalScript"), ("DisasterConfig", "ModuleScript"), ("DisasterGameManager", "Script")):
    src = read("scripts_ready_to_paste", name + ".lua")
    patched += item(cls, name, src, disabled=(cls == "Script"))  # off until moved (see INSTALL_NOTES)
    one = '<roblox xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="4">' + item(cls, name, src) + "</roblox>\n"
    with open(os.path.join(HERE, name + ".rbxmx"), "w", encoding="utf8", newline="\n") as fh:
        fh.write(one)
    print("wrote", name + ".rbxmx")

# Everything in one file: a "TuffUpdate" folder (insert into ServerScriptService, then run the
# one-line command from INSTALL_NOTES.md to move each script to its place)
lobby = item("Script", "LobbyUpgrade", sources["LobbyUpgrade"], run_context=0, children=children, disabled=True)
folder = '<Item class="Folder" referent="RBX_TuffUpdate"><Properties><string name="Name">TuffUpdate</string></Properties>%s</Item>' % (lobby + patched)
with open(os.path.join(HERE, "TuffUpdate_AllScripts.rbxmx"), "w", encoding="utf8", newline="\n") as fh:
    fh.write('<roblox xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="4">' + folder + "</roblox>\n")
print("wrote TuffUpdate_AllScripts.rbxmx")
