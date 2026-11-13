"""
blender_lobby_kit.py  -  builds every model for the lobby upgrade + disaster atmosphere.

Run headless:   blender -b -P blender_lobby_kit.py -- <output folder> [--no-render]
Or inside Blender: Scripting tab > Open > Run Script (files go next to the .blend, or your home folder).

Output:  LobbyKit.glb  (import this into Roblox Studio: File > Import 3D)
         LobbyKit.fbx  (backup format), LobbyKit.blend (editable scene), palette.lua, preview_*.png

Every mesh is named   Prop__piece__colorKey[__anim]
  Prop      which prop it belongs to (Hub, KioskShop, Pillar, Siren ...)
  colorKey  a key of PAL below - the Roblox script colours the mesh from it
  anim      optional: spin<deg/s> and/or bob<studs>, joined by "_"  (e.g. spin40_bob0.5)
Each prop also has a tiny "anchor" cube at its origin and (if it has a front) a "front" cube.
1 Blender unit = 1 stud.  Blender (x, y, z)  ->  Roblox (x, z, -y).
"""
import bpy, bmesh, math, os, sys, random
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
paths = [a for a in argv if not a.startswith("--")]
OUT = paths[0] if paths else (bpy.path.abspath("//") if bpy.data.filepath else os.path.expanduser("~"))
RENDER = "--no-render" not in argv
os.makedirs(OUT, exist_ok=True)
random.seed(11)
R = math.radians
I4 = Matrix.Identity(4)

# colorKey: (r, g, b, Roblox material, transparency)
PAL = {
    "stone":      (72, 78, 98, "Slate", 0),
    "stoneLight": (190, 198, 220, "Concrete", 0),
    "tile":       (52, 92, 190, "SmoothPlastic", 0),
    "tileLight":  (92, 150, 240, "SmoothPlastic", 0),
    "tileDark":   (28, 34, 64, "SmoothPlastic", 0),
    "white":      (245, 246, 250, "SmoothPlastic", 0),
    "black":      (30, 32, 40, "SmoothPlastic", 0),
    "gold":       (255, 196, 58, "SmoothPlastic", 0),
    "wood":       (160, 104, 58, "Wood", 0),
    "woodDark":   (100, 64, 40, "Wood", 0),
    "red":        (230, 64, 64, "SmoothPlastic", 0),
    "green":      (72, 200, 112, "SmoothPlastic", 0),
    "blue":       (70, 130, 255, "SmoothPlastic", 0),
    "purple":     (160, 96, 255, "SmoothPlastic", 0),
    "orange":     (255, 150, 50, "SmoothPlastic", 0),
    "orangeLight": (255, 186, 96, "SmoothPlastic", 0),
    "yellow":     (255, 214, 40, "SmoothPlastic", 0),
    "grass":      (96, 200, 84, "Grass", 0),
    "leaf":       (58, 168, 84, "Grass", 0),
    "rock":       (118, 106, 102, "Slate", 0),
    "rockDark":   (80, 72, 76, "Slate", 0),
    "metal":      (126, 134, 148, "Metal", 0),
    "cloudDark":  (62, 66, 90, "SmoothPlastic", 0.12),
    "cloudStorm": (112, 118, 146, "SmoothPlastic", 0.2),
    "cyanGlow":   (60, 230, 255, "Neon", 0),
    "pinkGlow":   (255, 90, 200, "Neon", 0),
    "goldGlow":   (255, 214, 90, "Neon", 0),
    "greenGlow":  (90, 255, 140, "Neon", 0),
    "orangeGlow": (255, 140, 40, "Neon", 0),
    "tint":       (255, 70, 70, "Neon", 0),   # recoloured per disaster by the Roblox script
    "x":          (255, 0, 255, "SmoothPlastic", 1),   # markers (anchor / front) - invisible in game
}


def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def RX(d): return Matrix.Rotation(R(d), 4, 'X')
def RY(d): return Matrix.Rotation(R(d), 4, 'Y')
def RZ(d): return Matrix.Rotation(R(d), 4, 'Z')
def S(x, y, z): return Matrix.Diagonal((x, y, z, 1))


# ------------------------------------------------------------------ mesh building
class Piece:
    def __init__(self):
        self.bm = bmesh.new()

    def box(self, size, loc, rot=None, bevel=0.0):
        m = T(*loc) @ (rot or I4) @ S(*size)
        r = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        if bevel > 0:
            edges = list({e for v in r["verts"] for e in v.link_edges})
            bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, segments=2, profile=0.5, affect='EDGES')
        return self

    def cyl(self, r1, r2, h, loc, seg=24, rot=None):
        """Cone/cylinder along +Z, base (radius r1) at loc, top (radius r2) at loc + h (before rot)."""
        m = T(*loc) @ (rot or I4) @ T(0, 0, h / 2)
        bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=seg,
                              radius1=max(r1, 0.0), radius2=max(r2, 0.0), depth=h, matrix=m)
        return self

    def sphere(self, r, loc, scale=(1, 1, 1), sub=2, rot=None):
        m = T(*loc) @ (rot or I4) @ S(*scale)
        bmesh.ops.create_icosphere(self.bm, subdivisions=sub, radius=r, matrix=m)
        return self

    def lathe(self, profile, loc=(0, 0, 0), seg=32, rot=None):
        """Revolve a closed (radius, z) profile around Z."""
        m = T(*loc) @ (rot or I4)
        rings = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            rings.append([self.bm.verts.new(m @ Vector((p[0] * math.cos(a), p[0] * math.sin(a), p[1]))) for p in profile])
        n = len(profile)
        for i in range(seg):
            a, b = rings[i], rings[(i + 1) % seg]
            for j in range(n):
                k = (j + 1) % n
                self.bm.faces.new((a[j], b[j], b[k], a[k]))
        return self

    def torus(self, R_, r_, loc, rot=None, seg=32, tube=8):
        prof = [(R_ + r_ * math.cos(2 * math.pi * t / tube), r_ * math.sin(2 * math.pi * t / tube)) for t in range(tube)]
        return self.lathe(prof, loc, seg, rot)

    def ring(self, r_in, r_out, h, loc, seg=48, rot=None):
        return self.lathe([(r_in, 0), (r_out, 0), (r_out, h), (r_in, h)], loc, seg, rot)

    def star(self, ro, ri, h, loc, points=5, rot=None):
        m = T(*loc) @ (rot or I4)
        bot, top = [], []
        for i in range(points * 2):
            a = math.pi * i / points + math.pi / 2
            r = ro if i % 2 == 0 else ri
            bot.append(self.bm.verts.new(m @ Vector((r * math.cos(a), r * math.sin(a), 0))))
            top.append(self.bm.verts.new(m @ Vector((r * math.cos(a), r * math.sin(a), h))))
        cb = self.bm.verts.new(m @ Vector((0, 0, 0)))
        ct = self.bm.verts.new(m @ Vector((0, 0, h)))
        n = points * 2
        for i in range(n):
            k = (i + 1) % n
            self.bm.faces.new((bot[i], bot[k], top[k], top[i]))
            self.bm.faces.new((top[i], top[k], ct))
            self.bm.faces.new((bot[k], bot[i], cb))
        return self


MATS = {}
PROPS = {}       # name -> {"origin": Vector, "objs": [objects]}
CUR = {"name": None, "origin": Vector((0, 0, 0))}
GRID = 320.0


def material(key):
    if key in MATS:
        return MATS[key]
    r, g, b, mat, tr = PAL[key]
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    col = tuple((c / 255.0) ** 2.2 for c in (r, g, b)) + (1.0,)
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = 0.55
    if mat == "Neon":
        bsdf.inputs["Emission Color"].default_value = col
        bsdf.inputs["Emission Strength"].default_value = 4.0
    if mat == "Metal":
        bsdf.inputs["Metallic"].default_value = 0.8
        bsdf.inputs["Roughness"].default_value = 0.35
    if tr > 0:
        bsdf.inputs["Alpha"].default_value = 1.0 - tr
    MATS[key] = m
    return m


def begin(name, front=False):
    i = len(PROPS)
    origin = Vector(((i % 4) * GRID, (i // 4) * GRID, 0))
    PROPS[name] = {"origin": origin, "objs": []}
    CUR["name"], CUR["origin"] = name, origin
    add("anchor", "x", Piece().box((0.2, 0.2, 0.2), (0, 0, 0)))
    if front:
        add("front", "x", Piece().box((0.2, 0.2, 0.2), (0, -2, 0)))


def add(piece, color, p, anim=None):
    bm = p.bm
    bmesh.ops.transform(bm, matrix=T(*CUR["origin"]), verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    sharp = R(38)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        e.smooth = len(e.link_faces) == 2 and e.calc_face_angle(0.0) < sharp
    name = "%s__%s__%s" % (CUR["name"], piece, color) + ("__" + anim if anim else "")
    assert len(name) < 60, name
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    mesh.materials.append(material(color))
    PROPS[CUR["name"]]["objs"].append(obj)
    return obj


# ------------------------------------------------------------------ props
def build_scale_ref():
    begin("ScaleRef")
    add("cube", "stone", Piece().box((10, 10, 10), (0, 0, 5)))


def build_hub():
    """The floating sky-island deck. Top of the deck is z = 0, 122 x 122 studs."""
    begin("Hub")
    add("deck", "stoneLight", Piece().box((122, 122, 2.2), (0, 0, -1.1), bevel=0.3))
    trim = Piece()
    for s in (-1, 1):
        trim.box((125, 2.2, 2.7), (0, s * 61.2, -1.2), bevel=0.2)
        trim.box((2.2, 125, 2.7), (s * 61.2, 0, -1.2), bevel=0.2)
    add("trim", "gold", trim)
    add("disc1", "tile", Piece().cyl(50, 50, 0.06, (0, 0, 0), seg=64))
    add("ringA", "cyanGlow", Piece().ring(50, 51.4, 0.1, (0, 0, 0), seg=64))
    add("disc2", "tileLight", Piece().cyl(30, 30, 0.1, (0, 0, 0), seg=48))
    add("ringB", "pinkGlow", Piece().ring(30, 31, 0.14, (0, 0, 0), seg=48))
    add("disc3", "tileDark", Piece().cyl(12, 12, 0.14, (0, 0, 0), seg=40))
    add("star", "gold", Piece().star(9.5, 4.2, 0.2, (0, 0, 0), points=8))
    add("projector", "cyanGlow", Piece().ring(12, 13.2, 0.35, (0, 0, 0), seg=40))
    spokes = Piece()
    for i in range(8):
        a = i * 45 + 22.5
        spokes.box((15, 0.7, 0.13), (math.cos(R(a)) * 21.5, math.sin(R(a)) * 21.5, 0.065), rot=RZ(a))
    add("spokes", "gold", spokes)
    # corner tiles
    corners = Piece()
    for sx in (-1, 1):
        for sy in (-1, 1):
            corners.box((14, 14, 0.08), (sx * 50, sy * 50, 0.04), rot=RZ(45))
    add("corners", "tile", corners)

    # fence
    posts, caps, railG, railW = Piece(), Piece(), Piece(), Piece()
    seen = set()
    for i in range(9):
        t = -60 + i * 15
        for (x, y) in ((t, -60), (t, 60), (-60, t), (60, t)):
            if (x, y) in seen:
                continue
            seen.add((x, y))
            big = abs(x) == 60 and abs(y) == 60
            w, h = (2.4, 6.2) if big else (1.6, 4.6)
            posts.box((w, w, h), (x, y, h / 2), bevel=0.15)
            caps.sphere(1.1 if big else 0.75, (x, y, h + 0.45), sub=2)
    for s in (-1, 1):
        railG.box((120, 0.35, 0.35), (0, s * 60, 3.7))
        railG.box((0.35, 120, 0.35), (s * 60, 0, 3.7))
        railW.box((120, 0.5, 0.5), (0, s * 60, 1.9))
        railW.box((0.5, 120, 0.5), (s * 60, 0, 1.9))
    add("posts", "white", posts)
    add("caps", "goldGlow", caps)
    add("railGlow", "cyanGlow", railG)
    add("rail", "white", railW)

    # rocky underside + hanging crystals
    add("rock1", "rockDark", Piece().cyl(60, 86, 13.6, (0, 0, -16), seg=4, rot=RZ(45)))
    add("rock2", "rock", Piece().cyl(22, 56, 24, (0, 0, -40), seg=8, rot=RZ(22.5)))
    add("rock3", "rockDark", Piece().cyl(0, 24, 30, (0, 0, -70), seg=6))
    cA, cB = Piece(), Piece()
    for i in range(10):
        a = R(i * 36 + random.uniform(-8, 8))
        rr = random.uniform(49, 55)
        ln = random.uniform(4, 8)
        w = random.uniform(1.1, 1.9)
        p = cA if i % 2 == 0 else cB
        x, y = math.cos(a) * rr, math.sin(a) * rr
        p.cyl(0, w, ln, (x, y, -17.5 - ln), seg=5)
        p.cyl(w, 0, ln * 0.3, (x, y, -17.5), seg=5)
    add("crystalsA", "cyanGlow", cA)
    add("crystalsB", "pinkGlow", cB)


def build_holo():
    """Floating centrepiece: a tiny island with a tornado, orbit rings and a meteor."""
    begin("Holo")
    isl = "spin12_bob0.8"
    add("grass", "grass", Piece().cyl(6.6, 7, 1.2, (0, 0, 20), seg=10), isl)
    rock = Piece().cyl(0, 6.6, 7, (0, 0, 13), seg=10)
    rock.cyl(0, 1.6, 3.4, (3, 2, 12.4), seg=5)
    add("rock", "rock", rock, isl)
    trees = Piece()
    for (x, y) in ((-4, 2), (3.6, -3.4), (-2.5, -4.2)):
        trees.sphere(1.3, (x, y, 22.6), sub=1)
    add("trees", "leaf", trees, isl)
    f = Piece()
    for i in range(7):
        rl = 0.5 + i * 0.8
        f.cyl(rl, rl + 1.0, 1.7, (math.sin(i * 1.1) * 0.55, math.cos(i * 1.3) * 0.55, 21.2 + i * 1.6), seg=12)
    add("funnel", "cloudStorm", f, "spin-170_bob0.8")
    add("ring1", "cyanGlow", Piece().torus(11, 0.3, (0, 0, 22), rot=RX(25), seg=48), "spin35")
    add("ring2", "pinkGlow", Piece().torus(12.6, 0.3, (0, 0, 22), rot=RZ(60) @ RX(-32), seg=48), "spin-50")
    add("ring3", "goldGlow", Piece().torus(14.2, 0.3, (0, 0, 22), rot=RZ(20) @ RY(68), seg=48), "spin70")
    add("meteor", "rockDark", Piece().sphere(1.5, (16, 0, 27), sub=1), "spin80")
    add("meteorTail", "orangeGlow", Piece().cyl(1.3, 0, 6, (16, -0.6, 27), seg=8, rot=RX(90)), "spin80")


def build_kiosk_shop():
    begin("KioskShop", front=True)
    add("counter", "wood", Piece().box((9, 7, 4.5), (0, 0, 2.25), bevel=0.2))
    add("top", "woodDark", Piece().box((10, 8, 0.5), (0, 0, 4.75), bevel=0.1))
    posts = Piece()
    for sx in (-1, 1):
        for sy in (-1, 1):
            posts.box((0.6, 0.6, 6.4), (sx * 4.5, sy * 3.5, 8.2))
    add("posts", "woodDark", posts)
    red, white = Piece(), Piece()
    for i in range(6):
        p = red if i % 2 == 0 else white
        p.box((1.84, 10.4, 0.45), (-4.6 + i * 1.84, -0.4, 11.5), rot=RX(-12))
        p.box((1.84, 0.4, 1.3), (-4.6 + i * 1.84, -5.5, 9.75))
    add("awningRed", "red", red)
    add("awningWhite", "white", white)
    add("sign", "gold", Piece().box((6.4, 0.6, 2.2), (0, 2.6, 13.8), bevel=0.15))
    add("bigCoin", "goldGlow", Piece().cyl(1.7, 1.7, 0.5, (0, 0.25, 17), seg=24, rot=RX(90)), "spin90_bob0.4")
    crates = Piece().box((2.6, 2.6, 2.6), (6.6, 0.6, 1.3), rot=RZ(12), bevel=0.12)
    crates.box((2, 2, 2), (6.4, 0.4, 3.6), rot=RZ(-20), bevel=0.1)
    crates.box((2.2, 2.2, 2.2), (-6.5, -1.2, 1.1), rot=RZ(30), bevel=0.1)
    add("crates", "woodDark", crates)
    for i, key in enumerate(("greenGlow", "pinkGlow", "cyanGlow")):
        x = -2.6 + i * 2.6
        pot = Piece().sphere(0.7, (x, -2.2, 5.7), sub=2).cyl(0.28, 0.22, 0.8, (x, -2.2, 6.2), seg=10)
        add("potion%d" % i, key, pot)


def build_kiosk_quests():
    begin("KioskQuests", front=True)
    add("base", "stone", Piece().box((11, 4, 1), (0, 0, 0.5), bevel=0.2))
    posts = Piece().box((0.9, 0.9, 10.5), (-4.6, 0, 5.25)).box((0.9, 0.9, 10.5), (4.6, 0, 5.25))
    add("posts", "woodDark", posts)
    add("board", "wood", Piece().box((9.2, 0.6, 6), (0, 0, 6), bevel=0.1))
    papers = Piece()
    for (x, z, a) in ((-2.7, 6.6, 6), (0.2, 5.6, -4), (2.9, 6.8, 3)):
        papers.box((2.2, 0.12, 2.9), (x, -0.36, z), rot=RY(a))
    add("papers", "white", papers)
    pins = Piece()
    for (x, z) in ((-2.7, 7.8), (0.2, 6.8), (2.9, 8.0)):
        pins.sphere(0.22, (x, -0.5, z), sub=1)
    add("pins", "red", pins)
    roof = Piece()
    roof.box((6.6, 3, 0.5), (-2.9, 0, 11.2), rot=RY(-22))
    roof.box((6.6, 3, 0.5), (2.9, 0, 11.2), rot=RY(22))
    add("roof", "blue", roof)
    mark = Piece().box((1, 1, 2.6), (0, 0, 15.3), bevel=0.2).box((1, 1, 1), (0, 0, 13.2), bevel=0.2)
    add("mark", "goldGlow", mark, "spin60_bob0.7")


def build_kiosk_daily():
    begin("KioskDaily", front=True)
    add("box", "orange", Piece().box((7.4, 7.4, 5.6), (0, 0, 2.8), bevel=0.3))
    rib = Piece().box((7.6, 1.5, 5.7), (0, 0, 2.85)).box((1.5, 7.6, 5.7), (0, 0, 2.85))
    add("ribbon", "white", rib)
    lid = "bob0.5"
    add("lid", "orangeLight", Piece().box((8.2, 8.2, 1.7), (0, 0, 6.9), bevel=0.3), lid)
    lr = Piece().box((8.4, 1.5, 1.8), (0, 0, 6.9)).box((1.5, 8.4, 1.8), (0, 0, 6.9))
    lr.torus(1.3, 0.42, (-1.3, 0, 8.6), rot=RY(-35) @ RX(90), seg=16)
    lr.torus(1.3, 0.42, (1.3, 0, 8.6), rot=RY(35) @ RX(90), seg=16)
    lr.sphere(0.7, (0, 0, 8.0), sub=1)
    add("lidRibbon", "white", lr, lid)
    stars = Piece()
    for i, (x, y, z) in enumerate(((5.6, 0, 9.5), (-5.2, 2, 11.5), (0.5, -1, 13.5))):
        stars.star(1.0, 0.45, 0.4, (x, y + 0.2, z), rot=RX(90))
    add("stars", "goldGlow", stars, "spin45")


def build_kiosk_board():
    begin("KioskBoard", front=True)
    add("step1", "purple", Piece().cyl(5.6, 5.6, 1.6, (0, 0, 0), seg=32))
    add("step2", "white", Piece().cyl(4.3, 4.3, 1.6, (0, 0, 1.6), seg=32))
    add("step3", "purple", Piece().cyl(3.1, 3.1, 1.6, (0, 0, 3.2), seg=32))
    t = Piece()
    t.cyl(1.5, 1.2, 0.6, (0, 0, 5.4), seg=20)
    t.cyl(0.4, 0.4, 1.7, (0, 0, 6.0), seg=12)
    t.cyl(0.9, 2.3, 2.8, (0, 0, 7.7), seg=24)
    t.torus(2.3, 0.22, (0, 0, 10.5), seg=24)
    t.torus(1.0, 0.24, (2.6, 0, 9.2), rot=RX(90), seg=16)
    t.torus(1.0, 0.24, (-2.6, 0, 9.2), rot=RX(90), seg=16)
    add("trophy", "gold", t, "spin45_bob0.3")
    add("trophyStar", "goldGlow", Piece().star(1.3, 0.6, 0.5, (0, 0.25, 12.6), rot=RX(90)), "spin45_bob0.3")


def build_sign_frame():
    """Frames an existing wall sign (sign plane at y = 0, x in [-16,16], z in [1,15])."""
    begin("SignFrame", front=True)
    cols, bases, caps = Piece(), Piece(), Piece()
    for s in (-1, 1):
        cols.box((2.4, 2.4, 18), (s * 18.6, 0, 9), bevel=0.25)
        bases.box((3.6, 3.6, 1.3), (s * 18.6, 0, 0.65), bevel=0.2)
        caps.box((3.2, 3.2, 0.8), (s * 18.6, 0, 18.4), bevel=0.15)
    add("columns", "white", cols)
    add("bases", "stone", bases)
    add("caps", "gold", caps)
    add("beam", "stone", Piece().box((43, 2.8, 2.4), (0, 0, 20), bevel=0.25))
    ped = Piece()
    ped.box((34, 2.6, 1.4), (0, 0, 21.9), bevel=0.15)
    ped.box((22, 2.6, 1.4), (0, 0, 23.3), bevel=0.15)
    ped.box((10, 2.6, 1.4), (0, 0, 24.7), bevel=0.15)
    add("pediment", "stoneLight", ped)
    add("glow", "cyanGlow", Piece().box((36, 0.5, 0.5), (0, -1.5, 18.5)))
    add("back", "tileDark", Piece().box((35.6, 0.6, 17.4), (0, 1.1, 9.3)))
    gem = Piece().cyl(0, 1.3, 1.6, (0, 0, 26.2), seg=6).cyl(1.3, 0, 1.6, (0, 0, 27.8), seg=6)
    add("gem", "pinkGlow", gem, "spin60_bob0.4")


def build_pillar():
    begin("Pillar")
    add("base", "stone", Piece().box((3.6, 3.6, 1.3), (0, 0, 0.65), bevel=0.25))
    add("shaft", "white", Piece().cyl(1.05, 0.8, 9, (0, 0, 1.3), seg=12))
    add("collar", "gold", Piece().torus(1.0, 0.3, (0, 0, 10.3), seg=20).cyl(0.7, 1.7, 1.2, (0, 0, 10.4), seg=12))
    cr = Piece().cyl(0, 1.25, 2.6, (0, 0, 12.4), seg=6).cyl(1.25, 0, 1.5, (0, 0, 15), seg=6)
    add("crystal", "cyanGlow", cr, "spin50_bob0.5")
    add("halo", "pinkGlow", Piece().torus(2.1, 0.14, (0, 0, 14.4), seg=28), "spin-90_bob0.5")


def build_float_island():
    """Small floating island with a tree. Top surface is z = 0."""
    begin("FloatIsland")
    add("grass", "grass", Piece().cyl(8, 8.4, 1.4, (0, 0, -1.4), seg=9))
    rock = Piece().cyl(0, 8.2, 11, (0, 0, -12.4), seg=9)
    rock.cyl(0, 2.6, 5.5, (4.5, -3, -9), seg=5)
    rock.cyl(0, 2, 4, (-5, 2.5, -7), seg=5)
    add("rock", "rock", rock)
    stones = Piece().sphere(1.2, (-4.5, -3.2, 0.3), scale=(1, 0.8, 0.6), sub=1).sphere(0.8, (-2.6, -4.6, 0.2), scale=(1, 1, 0.6), sub=1)
    add("stones", "stoneLight", stones)
    add("trunk", "wood", Piece().cyl(0.75, 0.5, 4.4, (4.5, 3, 0), seg=8))
    leaves = Piece().sphere(2.7, (4.5, 3, 5.6), sub=1).sphere(2.1, (3.2, 2.2, 7.6), sub=1).sphere(1.9, (5.8, 3.8, 7.2), sub=1)
    add("leaves", "leaf", leaves)


def build_balloon():
    """Hot-air balloon. Origin = centre of the envelope."""
    begin("Balloon")
    add("envelope", "red", Piece().sphere(7, (0, 0, 0), scale=(1, 1, 1.15), sub=3))
    bands = Piece().torus(6.42, 0.8, (0, 0, 3), seg=32).torus(6.42, 0.8, (0, 0, -3), seg=32)
    bands.sphere(2.2, (0, 0, 7.5), scale=(1, 1, 0.4), sub=2)
    add("bands", "white", bands)
    add("skirt", "yellow", Piece().cyl(1.6, 4.75, 4.5, (0, 0, -10.5), seg=20))
    add("basket", "wood", Piece().box((3.2, 3.2, 2.4), (0, 0, -14.6), bevel=0.2))
    ropes = Piece().box((3.6, 3.6, 0.4), (0, 0, -13.3), bevel=0.1)
    for sx in (-1, 1):
        for sy in (-1, 1):
            ropes.cyl(0.09, 0.09, 3.2, (sx * 1.45, sy * 1.45, -13.4), seg=6)
    add("ropes", "woodDark", ropes)
    add("flame", "orangeGlow", Piece().cyl(0.6, 0, 1.7, (0, 0, -12.6), seg=8))


def build_step():
    """Floating stepping stone. Top surface is z = 0."""
    begin("Step")
    add("top", "stoneLight", Piece().cyl(3.4, 3.6, 0.9, (0, 0, -0.9), seg=6))
    add("glow", "cyanGlow", Piece().cyl(3.75, 3.75, 0.25, (0, 0, -1.15), seg=6))
    add("rock", "rock", Piece().cyl(0, 3.2, 3.6, (0, 0, -4.75), seg=6))


def build_chest():
    begin("Chest", front=True)
    add("body", "woodDark", Piece().box((5, 3.2, 2.6), (0, 0, 1.3), bevel=0.15))
    bands = Piece().box((0.55, 3.4, 2.8), (-1.6, 0, 1.35)).box((0.55, 3.4, 2.8), (1.6, 0, 1.35))
    add("bands", "gold", bands)
    add("glow", "goldGlow", Piece().box((4.4, 2.6, 0.5), (0, 0, 2.75)))
    lid = "bob0.25"
    add("lid", "wood", Piece().cyl(1.6, 1.6, 5, (-2.5, 0, 3.2), seg=20, rot=RY(90)), lid)
    lb = Piece().cyl(1.72, 1.72, 0.55, (-1.875, 0, 3.2), seg=20, rot=RY(90)).cyl(1.72, 1.72, 0.55, (1.325, 0, 3.2), seg=20, rot=RY(90))
    lb.box((0.9, 0.4, 1.1), (0, -1.75, 2.9), bevel=0.08)
    add("lidBands", "gold", lb, lid)
    coins = Piece()
    for (x, y, a) in ((3.4, -1.2, 0), (3.9, 0.6, 20), (-3.5, -0.8, -15), (3.2, -0.4, 40)):
        coins.cyl(0.6, 0.6, 0.18, (x, y, 0.0 if a != 40 else 0.18), seg=12)
    add("coins", "goldGlow", coins)


def build_jump_pad():
    begin("JumpPad")
    add("base", "tileDark", Piece().cyl(4.2, 4, 0.45, (0, 0, 0), seg=24))
    add("top", "greenGlow", Piece().cyl(3.4, 3.4, 0.35, (0, 0, 0.45), seg=24))
    ch = Piece()
    for y in (-0.2, 1.4):
        ch.box((2.3, 0.5, 0.12), (-0.85, y - 0.55, 0.86), rot=RZ(35))
        ch.box((2.3, 0.5, 0.12), (0.85, y - 0.55, 0.86), rot=RZ(-35))
    add("arrows", "white", ch)
    add("rim", "white", Piece().torus(3.9, 0.2, (0, 0, 0.5), seg=32))


def build_coin():
    begin("Coin")
    a = "spin150"
    c = Piece().cyl(1.5, 1.5, 0.45, (0, 0.225, 0), seg=28, rot=RX(90))
    c.torus(1.5, 0.24, (0, 0, 0), rot=RX(90), seg=28)
    add("disc", "gold", c, a)
    add("star", "goldGlow", Piece().star(0.95, 0.42, 0.62, (0, 0.31, 0), rot=RX(90)), a)


def build_siren():
    """Emergency siren tower that rises out of the island when a disaster starts."""
    begin("Siren")
    add("base", "stone", Piece().box((5, 5, 1.2), (0, 0, 0.6), bevel=0.2))
    add("collar", "yellow", Piece().cyl(1.3, 1.3, 1.3, (0, 0, 1.2), seg=12))
    bands = Piece().cyl(1.36, 1.36, 0.4, (0, 0, 1.65), seg=12).cyl(0.75, 0.75, 0.5, (0, 0, 9), seg=12)
    add("bands", "black", bands)
    pole = Piece().cyl(0.62, 0.5, 17, (0, 0, 1.2), seg=10).cyl(2.2, 2.2, 0.4, (0, 0, 18.2), seg=16)
    pole.cyl(0.9, 0.9, 2.6, (0, 0, 18.6), seg=10)
    add("pole", "metal", pole)
    horns = Piece()
    for i in range(4):
        a = i * 90 + 45
        horns.cyl(0.45, 1.6, 2.8, (math.cos(R(a)) * 0.8, math.sin(R(a)) * 0.8, 19.8), seg=14, rot=RZ(a) @ RY(90))
    add("horns", "yellow", horns)
    b = Piece().sphere(1.35, (0, 0, 22.6), sub=2)
    b.cyl(0.3, 1.15, 1.9, (0.9, 0, 22.6), seg=10, rot=RY(90))
    b.cyl(0.3, 1.15, 1.9, (-0.9, 0, 22.6), seg=10, rot=RY(-90))
    add("beacon", "tint", b, "spin220")


def build_storm_ring():
    """Huge spiral storm cloud that spins above the island. ~100 studs radius before scaling."""
    begin("StormRing")
    for layer, (key, anim, lift, turn, sc, arms, count) in enumerate((
            ("cloudDark", "spin14", 0, 0, 1.0, 4, 22),
            ("cloudStorm", "spin9", 5, 45, 0.82, 4, 20))):
        p = Piece()
        for arm in range(arms):
            for k in range(count):
                a = R(arm * 360 / arms + k * 13 + turn)
                rr = (24 + k * 3.5) * sc
                rad = (8 + random.uniform(0, 5) + k * 0.12) * sc
                p.sphere(rad, (math.cos(a) * rr, math.sin(a) * rr, lift + random.uniform(-2, 2)),
                         scale=(1, 1, 0.38), sub=1, rot=RZ(random.uniform(0, 360)))
        add("arms%d" % layer, key, p, anim)
    add("eye", "tint", Piece().torus(19, 2.4, (0, 0, 1), seg=40, tube=8), "spin-30")
    add("eyeGlow", "tint", Piece().ring(52, 55, 0.6, (0, 0, -3), seg=56), "spin-20")


BUILDERS = [build_scale_ref, build_hub, build_holo, build_kiosk_shop, build_kiosk_quests, build_kiosk_daily,
            build_kiosk_board, build_sign_frame, build_pillar, build_float_island, build_balloon, build_step,
            build_chest, build_jump_pad, build_coin, build_siren, build_storm_ring]

# ------------------------------------------------------------------ build + export
bpy.ops.wm.read_factory_settings(use_empty=True)
for b in BUILDERS:
    b()

total = 0
for name, prop in PROPS.items():
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in prop["objs"])
    worst = max(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in prop["objs"])
    total += tris
    print("  %-12s %3d meshes %6d tris (largest mesh %d)" % (name, len(prop["objs"]), tris, worst))
print("TOTAL", sum(len(p["objs"]) for p in PROPS.values()), "meshes,", total, "tris")

with open(os.path.join(OUT, "palette.lua"), "w") as fh:
    for key, (r, g, b, mat, tr) in PAL.items():
        fh.write('\t%s = { Color3.fromRGB(%d, %d, %d), "%s", %s },\n' % (key, r, g, b, mat, tr))

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "LobbyKit.blend"))
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "LobbyKit.glb"), export_format='GLB',
                          export_apply=True, export_yup=True)
try:
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, "LobbyKit.fbx"), object_types={'MESH'},
                             global_scale=1.0, apply_scale_options='FBX_SCALE_ALL', axis_forward='-Z', axis_up='Y')
except Exception as e:  # FBX is only a backup format
    print("FBX export skipped:", e)
print("exported to", OUT)

# ------------------------------------------------------------------ preview renders (assembled lobby)
if RENDER:
    scene = bpy.context.scene
    for prop in PROPS.values():
        for o in prop["objs"]:
            o.hide_render = True

    def place(name, X, Y, Z, face_center=False, scale=1.0, yaw=0.0):
        """Roblox-style coordinates relative to the lobby floor top: X east, Y up, Z south."""
        loc = Vector((X, -Z, Y))
        if face_center:
            yaw = math.degrees(math.atan2(-loc.y, -loc.x)) + 90
        m = T(*loc) @ RZ(yaw) @ S(scale, scale, scale) @ T(*(-PROPS[name]["origin"]))
        for o in PROPS[name]["objs"]:
            if o.name.endswith("__x"):
                continue
            d = bpy.data.objects.new("pv_" + o.name, o.data)
            d.matrix_world = m
            scene.collection.objects.link(d)

    def lobby():
        place("Hub", 0, 0.05, 0)
        place("Holo", 0, 10, 0)
        for name, x in (("KioskShop", -36), ("KioskQuests", -12), ("KioskDaily", 12), ("KioskBoard", 36)):
            place(name, x, 0, 50, face_center=True)
        for (x, z) in ((-56, 0), (0, -56), (56, 0)):
            place("SignFrame", x, 0, z, face_center=True)
        for (x, z) in ((54, 54), (-54, 54), (54, -54), (-54, -54), (54, 34), (-54, 34), (54, -34), (-54, -34), (34, -54), (-34, -54)):
            place("Pillar", x, 0, z)
        for (x, y, z, s) in ((105, 6, -70, 1.6), (-110, -8, -40, 2.1), (-95, 16, 80, 1.3), (100, -4, 75, 1.8), (20, 20, -120, 1.5), (-30, -12, 118, 1.2)):
            place("FloatIsland", x, y, z, scale=s, yaw=x)
        place("Balloon", 85, 44, -40)
        place("Balloon", -80, 52, 55, yaw=40)
        steps = ((31, 3.5, -5), (23, 7.5, -8), (16, 11.5, -13), (14, 15.5, -22), (19, 19.5, -30), (26, 23.5, -37))
        for (x, y, z) in steps:
            place("Step", x, y, z, yaw=x * 7)
        place("FloatIsland", 40, 26.5, -40, scale=1.5)
        place("Chest", 41, 26.5, -42, face_center=True, scale=1.5)
        place("JumpPad", -34, 0, -34)
        place("JumpPad", -34, 0, 28)
        for i in range(1, 11):
            a = i / 10 * math.pi * 2
            rr = 20 if i % 2 == 0 else 36
            place("Coin", math.cos(a) * rr, 3, math.sin(a) * rr, yaw=i * 37)

    def camera(pos, target, lens=28):
        cam_data = bpy.data.cameras.new("cam")
        cam_data.lens = lens
        cam_data.clip_end = 5000
        cam = bpy.data.objects.new("cam", cam_data)
        cam.location = pos
        cam.rotation_euler = (Vector(target) - Vector(pos)).to_track_quat('-Z', 'Y').to_euler()
        scene.collection.objects.link(cam)
        scene.camera = cam

    lobby()
    place("StormRing", 600, 150, 0, scale=1.6)
    for (dx, dz) in ((-45, -30), (40, -40), (-35, 45), (50, 35)):
        place("Siren", 600 + dx, 0, dz, scale=1.5)
    ground = bpy.data.objects.new("pv_ground", bpy.data.meshes.new("g"))
    gp = Piece().box((230, 230, 6), (600, 0, -3), bevel=1)
    gp.bm.to_mesh(ground.data)
    ground.data.materials.append(material("grass"))
    scene.collection.objects.link(ground)

    world = bpy.data.worlds.new("sky")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.32, 0.55, 0.95, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.1
    scene.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN'))
    sun.data.energy = 3.5
    sun.data.angle = R(4)
    sun.rotation_euler = (R(50), 0, R(35))
    scene.collection.objects.link(sun)

    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 40
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    scene.view_settings.view_transform = 'Standard'

    shots = (
        ("preview_lobby_wide", (120, 150, 95), (0, -5, 8), 26),
        ("preview_lobby_kiosks", (0, 22, 16), (0, -52, 7), 22),
        ("preview_lobby_parkour", (-30, -18, 26), (30, 30, 16), 22),
        ("preview_disaster", (600 + 150, -170, 60), (600, 0, 70), 22),
    )
    for name, pos, target, lens in shots:
        camera(pos, target, lens)
        scene.render.filepath = os.path.join(OUT, name + ".png")
        try:
            bpy.ops.render.render(write_still=True)
            print("rendered", name)
        except Exception as e:
            print("render failed", name, e)
