# Anatomy figures — spinning machines (3D)

Interactive isometric figures built with [Anatomy](https://skills.wheresryan.sh/anatomy) in **3D** mode.

| Figure | Open | Interaction |
|------|------|-------------|
| Water frame (Arkwright, 1775) | `water-frame/water-frame.html` | Drag drive pulley · Space run · S slow |
| Spinning mule (Crompton) | `spinning-mule/spinning-mule.html` | Drag carriage · Space cycle · S slow |

HTML is standalone (kit inlined). Truth models: roller ratios `1 : 1.6 : 18.4` (overall draft 18.4×); mule draw 1.52 m with intermittent draw/twist then wind.

To rebuild, check out [wheresryan22/anatomy](https://github.com/wheresryan22/anatomy), put `kit/` and `scripts/` beside these folders (or symlink), then `node build.mjs` / `node build.mjs --light`.
