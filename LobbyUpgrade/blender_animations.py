"""
blender_animations.py - walk / run / swim cycles for R15 characters, keyframed in Blender.

Run headless:  blender -b -P blender_animations.py -- <output folder>

Every R15 joint gets an animated empty per clip. The poses below are the keyframes; Blender's
Bezier curves (with a Cycles modifier, so every loop is seamless) fill in the motion. The curves are
then sampled and written to src/BlenderAnims.lua, which BlenderAnimator plays in game by setting each
Motor6D.Transform - no animation upload needed.

Angles are in the Roblox joint's own space: CFrame.Angles(x, y, z) (X = swing forward/back,
Y = twist, Z = sideways). +X on a hip/shoulder swings the limb forward; -X on a knee bends it.
Also renders preview_animations.png (a stick figure in 8 poses per clip) and stud_tile.png
(the shop's studded texture tile).
"""
import bpy, math, os, sys
from mathutils import Matrix, Vector, Euler

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else os.path.dirname(os.path.abspath(__file__))
HERE = os.path.dirname(os.path.abspath(__file__))
FPS = 30
SAMPLES = 32
PI = math.pi

JOINTS = ["Root", "Waist", "Neck", "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow",
          "LeftHip", "RightHip", "LeftKnee", "RightKnee", "LeftAnkle", "RightAnkle"]
MIRROR = {"Left": "Right", "Right": "Left"}


def mirror_name(j):
    for a, b in MIRROR.items():
        if j.startswith(a):
            return b + j[len(a):]
    return j


def mirrored(pose):
    """Same pose on the other side: swap left/right, flip twist (Y) and sideways (Z)."""
    out = {}
    for j, v in pose.items():
        if j == "RootY":
            out[j] = v
            continue
        x, y, z = (list(v) + [0, 0, 0])[:3]
        out[mirror_name(j)] = (x, -y, -z)
    return out


# ------------------------------------------------------------------ poses (first half of each stride)
WALK_HALF = {
    0.000: {"RightHip": (0.42,), "RightKnee": (-0.06,), "RightAnkle": (0.10,), "LeftHip": (-0.38,), "LeftKnee": (-0.28,), "LeftAnkle": (-0.25,),
            "RightShoulder": (-0.32,), "LeftShoulder": (0.32,), "RightElbow": (0.25,), "LeftElbow": (0.35,),
            "Waist": (-0.04, 0.07, 0), "Neck": (0.02, -0.03, 0), "Root": (0, 0, 0.02), "RootY": -0.06},
    0.125: {"RightHip": (0.28,), "RightKnee": (-0.28,), "RightAnkle": (0.0,), "LeftHip": (-0.28,), "LeftKnee": (-0.55,), "LeftAnkle": (-0.10,),
            "RightShoulder": (-0.22,), "LeftShoulder": (0.22,), "RightElbow": (0.25,), "LeftElbow": (0.30,),
            "Waist": (-0.04, 0.05, 0), "Neck": (0.02, -0.02, 0), "Root": (0, 0, 0.03), "RootY": -0.14},
    0.250: {"RightHip": (0.02,), "RightKnee": (-0.12,), "RightAnkle": (0.0,), "LeftHip": (0.12,), "LeftKnee": (-0.95,), "LeftAnkle": (0.10,),
            "RightShoulder": (0.0,), "LeftShoulder": (0.0,), "RightElbow": (0.25,), "LeftElbow": (0.25,),
            "Waist": (-0.04, 0.0, 0), "Neck": (0.02, 0.0, 0), "Root": (0, 0, 0.0), "RootY": 0.04},
    0.375: {"RightHip": (-0.22,), "RightKnee": (-0.05,), "RightAnkle": (-0.10,), "LeftHip": (0.32,), "LeftKnee": (-0.45,), "LeftAnkle": (0.20,),
            "RightShoulder": (0.20,), "LeftShoulder": (-0.20,), "RightElbow": (0.30,), "LeftElbow": (0.25,),
            "Waist": (-0.04, -0.04, 0), "Neck": (0.02, 0.02, 0), "Root": (0, 0, -0.01), "RootY": 0.07},
}
RUN_HALF = {
    0.000: {"RightHip": (0.80,), "RightKnee": (-0.25,), "RightAnkle": (0.20,), "LeftHip": (-0.55,), "LeftKnee": (-0.90,), "LeftAnkle": (-0.30,),
            "RightShoulder": (-0.85,), "LeftShoulder": (0.85,), "RightElbow": (1.30,), "LeftElbow": (1.30,),
            "Waist": (-0.20, 0.15, 0), "Neck": (0.14, -0.08, 0), "Root": (-0.06, 0, 0.03), "RootY": -0.10},
    0.125: {"RightHip": (0.45,), "RightKnee": (-0.55,), "RightAnkle": (0.05,), "LeftHip": (-0.35,), "LeftKnee": (-1.50,), "LeftAnkle": (-0.10,),
            "RightShoulder": (-0.50,), "LeftShoulder": (0.50,), "RightElbow": (1.35,), "LeftElbow": (1.25,),
            "Waist": (-0.20, 0.10, 0), "Neck": (0.14, -0.05, 0), "Root": (-0.06, 0, 0.04), "RootY": -0.28},
    0.250: {"RightHip": (-0.05,), "RightKnee": (-0.35,), "RightAnkle": (0.0,), "LeftHip": (0.55,), "LeftKnee": (-1.90,), "LeftAnkle": (0.30,),
            "RightShoulder": (0.10,), "LeftShoulder": (-0.10,), "RightElbow": (1.30,), "LeftElbow": (1.30,),
            "Waist": (-0.20, 0.0, 0), "Neck": (0.14, 0.0, 0), "Root": (-0.06, 0, 0.0), "RootY": 0.05},
    0.375: {"RightHip": (-0.45,), "RightKnee": (-0.60,), "RightAnkle": (-0.30,), "LeftHip": (0.85,), "LeftKnee": (-1.00,), "LeftAnkle": (0.25,),
            "RightShoulder": (0.70,), "LeftShoulder": (-0.70,), "RightElbow": (1.25,), "LeftElbow": (1.35,),
            "Waist": (-0.20, -0.10, 0), "Neck": (0.14, 0.05, 0), "Root": (-0.06, 0, -0.03), "RootY": 0.22},
}


def full_cycle(half):
    keys = {}
    for t, pose in half.items():
        keys[t] = pose
        keys[t + 0.5] = mirrored(pose)
    keys[1.0] = half[0.0]
    return keys


def swim_cycle():
    """Front crawl: arms windmill (continuous, LINEAR), legs flutter-kick, body rolls, breathe to the right."""
    keys = {}
    for i in range(17):
        t = i / 16
        kick = math.sin(2 * PI * 3 * t)
        breathe = max(0.0, math.sin(2 * PI * (t - 0.55))) ** 2
        keys[t] = {
            "Root": (-1.45, 0, 0.35 * math.sin(2 * PI * t)),
            "RightShoulder": (PI - 2 * PI * t, 0, 0),
            "LeftShoulder": (-2 * PI * t, 0, 0),
            "RightElbow": (0.35 + 0.55 * max(0, math.sin(2 * PI * (t - 0.5))),),
            "LeftElbow": (0.35 + 0.55 * max(0, math.sin(2 * PI * t)),),
            "RightHip": (0.22 * kick,), "LeftHip": (-0.22 * kick,),
            "RightKnee": (-0.18 - 0.14 * (kick + 1) / 2,), "LeftKnee": (-0.18 - 0.14 * (1 - kick) / 2,),
            "RightAnkle": (-0.5,), "LeftAnkle": (-0.5,),
            "Waist": (0.1, 0, 0), "Neck": (0.35, 0.9 * breathe, 0),
            "RootY": 0.0,
        }
    return keys


CLIPS = {
    "walk": {"length": 1.00, "keys": full_cycle(WALK_HALF), "linear": set()},
    "run": {"length": 0.66, "keys": full_cycle(RUN_HALF), "linear": set()},
    "swim": {"length": 1.40, "keys": swim_cycle(), "linear": {("RightShoulder", 0), ("LeftShoulder", 0)}},
}

# ------------------------------------------------------------------ keyframe everything in Blender
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = FPS


def channel_values(keys, joint, axis):
    vals = {}
    for t, pose in keys.items():
        if joint == "RootY":
            if "RootY" in pose:
                vals[t] = pose["RootY"]
        elif joint in pose:
            v = (list(pose[joint]) + [0, 0, 0])[:3]
            vals[t] = v[axis]
    return vals


curves = {}  # (clip, joint, axis) -> fcurve
for clip_name, clip in CLIPS.items():
    frames = clip["length"] * FPS
    for joint in JOINTS + ["RootY"]:
        ob = bpy.data.objects.new("%s_%s" % (clip_name, joint), None)
        scene.collection.objects.link(ob)
        for axis in ((1,) if joint == "RootY" else (0, 1, 2)):
            vals = channel_values(clip["keys"], joint, axis)
            if not vals:
                continue
            path, index = ("location", 2) if joint == "RootY" else ("rotation_euler", axis)
            for t, v in sorted(vals.items()):
                if path == "location":
                    ob.location[index] = v
                else:
                    ob.rotation_euler[index] = v
                ob.keyframe_insert(data_path=path, index=index, frame=1 + t * frames)
            fc = ob.animation_data.action.fcurves.find(path, index=index) if hasattr(ob.animation_data.action, "fcurves") else None
            if fc is None:  # Blender 5 layered actions
                for layer in ob.animation_data.action.layers:
                    for strip in layer.strips:
                        for bag in strip.channelbags:
                            f = bag.fcurves.find(path, index=index)
                            if f:
                                fc = f
            linear = (joint, axis) in clip["linear"]
            for kp in fc.keyframe_points:
                kp.interpolation = 'LINEAR' if linear else 'BEZIER'
                kp.handle_left_type = kp.handle_right_type = 'AUTO_CLAMPED'
            if not linear:
                fc.modifiers.new('CYCLES')  # seamless loop: the curve wraps around end -> start
            fc.update()
            curves[(clip_name, joint, axis)] = fc

# ------------------------------------------------------------------ sample + write Lua
def sample(clip_name, joint, axis):
    clip = CLIPS[clip_name]
    frames = clip["length"] * FPS
    fc = curves.get((clip_name, joint, axis))
    if fc is None:
        return None
    return [fc.evaluate(1 + frames * i / SAMPLES) for i in range(SAMPLES)]


lines = ["-- BlenderAnims  (ModuleScript, child of the LobbyUpgrade script)",
         "-- GENERATED by blender_animations.py - keyframed in Blender, sampled %d times per loop." % SAMPLES,
         "-- joints[name][i] = { x, y, z } for CFrame.Angles; rootY[i] = hip height offset (studs).",
         "return {", "\tsamples = %d," % SAMPLES, "\tclips = {"]
for clip_name, clip in CLIPS.items():
    lines.append("\t\t%s = {" % clip_name)
    lines.append("\t\t\tlength = %.2f," % clip["length"])
    ry = sample(clip_name, "RootY", 1)
    lines.append("\t\t\trootY = { %s }," % ", ".join("%.3f" % v for v in (ry or [0] * SAMPLES)))
    lines.append("\t\t\tjoints = {")
    for joint in JOINTS:
        xs = [sample(clip_name, joint, a) for a in (0, 1, 2)]
        if all(x is None for x in xs):
            continue
        xs = [x or [0.0] * SAMPLES for x in xs]
        frames = ", ".join("{%.3f, %.3f, %.3f}" % (xs[0][i], xs[1][i], xs[2][i]) for i in range(SAMPLES))
        lines.append("\t\t\t\t%s = { %s }," % (joint, frames))
    lines.append("\t\t\t},")
    lines.append("\t\t},")
lines += ["\t},", "}", ""]
lua_path = os.path.join(HERE, "src", "BlenderAnims.lua")
with open(lua_path, "w", encoding="utf8", newline="\n") as fh:
    fh.write("\n".join(lines))
print("wrote", lua_path)

# ------------------------------------------------------------------ preview: stick figure, 8 poses per clip
# simplified R15 layout (Roblox coords, studs): joint position in its parent part, and the child part's centre
SKEL = {  # joint: (parent joint or None, joint position relative to parent joint, child box size, child box centre from joint)
    "Root": (None, (0, 0, 0), (2.0, 0.6, 1.0), (0, 0.1, 0)),
    "Waist": ("Root", (0, 0.4, 0), (2.0, 1.6, 1.0), (0, 0.8, 0)),
    "Neck": ("Waist", (0, 1.6, 0), (1.2, 1.2, 1.2), (0, 0.6, 0)),
    "RightShoulder": ("Waist", (1.5, 1.4, 0), (1.0, 1.1, 1.0), (0, -0.45, 0)),
    "LeftShoulder": ("Waist", (-1.5, 1.4, 0), (1.0, 1.1, 1.0), (0, -0.45, 0)),
    "RightElbow": ("RightShoulder", (0, -1.0, 0), (1.0, 1.0, 1.0), (0, -0.5, 0)),
    "LeftElbow": ("LeftShoulder", (0, -1.0, 0), (1.0, 1.0, 1.0), (0, -0.5, 0)),
    "RightHip": ("Root", (0.5, -0.2, 0), (1.0, 1.2, 1.0), (0, -0.6, 0)),
    "LeftHip": ("Root", (-0.5, -0.2, 0), (1.0, 1.2, 1.0), (0, -0.6, 0)),
    "RightKnee": ("RightHip", (0, -1.2, 0), (1.0, 1.1, 1.0), (0, -0.55, 0)),
    "LeftKnee": ("LeftHip", (0, -1.2, 0), (1.0, 1.1, 1.0), (0, -0.55, 0)),
    "RightAnkle": ("RightKnee", (0, -1.1, 0), (1.0, 0.3, 1.4), (0, -0.15, -0.2)),
    "LeftAnkle": ("LeftKnee", (0, -1.1, 0), (1.0, 0.3, 1.4), (0, -0.15, -0.2)),
}
R2B = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # Roblox (x, y, z) -> Blender (x, -z, y)


def angles(x, y, z):
    return Euler((x, y, z), 'ZYX').to_matrix().to_4x4()  # = Rx @ Ry @ Rz, like CFrame.Angles


mats = {}
for name in ("Skin", "Shirt", "Pants"):
    m = bpy.data.materials.new(name)
    m.diffuse_color = {"Skin": (1.0, 0.8, 0.55, 1), "Shirt": (0.2, 0.45, 1.0, 1), "Pants": (0.15, 0.15, 0.2, 1)}[name]
    mats[name] = m
part_mat = {"Neck": "Skin", "RightElbow": "Skin", "LeftElbow": "Skin", "Root": "Pants", "RightHip": "Pants", "LeftHip": "Pants",
            "RightKnee": "Pants", "LeftKnee": "Pants", "RightAnkle": "Pants", "LeftAnkle": "Pants"}


def pose_figure(clip_name, phase, offset):
    i0 = int(phase * SAMPLES) % SAMPLES
    world = {}
    rooty = sample(clip_name, "RootY", 1)
    for joint in JOINTS:
        parent, jpos, size, centre = SKEL[joint]
        vals = [sample(clip_name, joint, a) for a in (0, 1, 2)]
        x, y, z = [(v[i0] if v else 0.0) for v in vals]
        base = Matrix.Translation((0, 3.2 + (rooty[i0] if rooty else 0), 0)) if parent is None else world[parent]
        world[joint] = base @ Matrix.Translation(jpos) @ angles(x, y, z)
        bpy.ops.mesh.primitive_cube_add(size=1)
        ob = bpy.context.object
        ob.matrix_world = Matrix.Translation(offset) @ R2B @ world[joint] @ Matrix.Translation(centre) @ Matrix.Diagonal((*size, 1))
        ob.data.materials.append(mats[part_mat.get(joint, "Shirt")])


# figures face Blender +Y (Roblox -Z); lay them out along Y and look from the side (+X toward -X)
for row, clip_name in enumerate(("walk", "run", "swim")):
    for col in range(8):
        pose_figure(clip_name, col / 8, Vector((0, col * 6.0, -row * 9.0)))

scene.render.engine = 'BLENDER_WORKBENCH'
scene.display.shading.light = 'STUDIO'
scene.display.shading.color_type = 'MATERIAL'
scene.render.resolution_x, scene.render.resolution_y = 1400, 800
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
cam.data.type = 'ORTHO'
cam.data.ortho_scale = 52
cam.location = (60, 21, -6)
cam.rotation_euler = (math.radians(90), 0, math.radians(90))  # looking toward -X, +Z up
scene.collection.objects.link(cam)
scene.camera = cam
world = bpy.data.worlds.new("w")
scene.world = world
scene.render.filepath = os.path.join(OUT, "preview_animations.png")
bpy.ops.render.render(write_still=True)
print("rendered preview_animations.png")

# ------------------------------------------------------------------ stud tile for the shop (seamless, 2 x 2 studs)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
plate = bpy.data.materials.new("plate")
plate.use_nodes = True
plate.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.85, 0.85, 0.88, 1)
plate.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.35
bpy.ops.mesh.primitive_plane_add(size=2)
bpy.context.object.data.materials.append(plate)
for x in (-0.5, 0.5):
    for y in (-0.5, 0.5):
        bpy.ops.mesh.primitive_cylinder_add(radius=0.3, depth=0.17, location=(x, y, 0.085), vertices=48)
        bpy.ops.object.shade_smooth()
        bpy.context.object.data.materials.append(plate)
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN'))
sun.data.energy = 4
sun.rotation_euler = (math.radians(35), 0, math.radians(150))  # light from the top-left: studs read as raised
scene.collection.objects.link(sun)
w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[1].default_value = 0.6
scene.world = w
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
cam.data.type = 'ORTHO'
cam.data.ortho_scale = 2
cam.location = (0, 0, 5)
scene.collection.objects.link(cam)
scene.camera = cam
scene.render.engine = 'CYCLES'
scene.cycles.samples = 32
scene.cycles.device = 'CPU'
scene.render.resolution_x = scene.render.resolution_y = 256
scene.view_settings.view_transform = 'Standard'
scene.render.filepath = os.path.join(OUT, "stud_tile.png")
bpy.ops.render.render(write_still=True)
print("rendered stud_tile.png")
