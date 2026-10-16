/**
 * Water frame (Arkwright, 1775) — Hero, 3D.
 * The object is continuous roller drafting + flyer twist, driven by a water wheel.
 * Drag the wheel (or hold Space) to run: rollers and flyers follow the same model.
 */
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as k from "../kit/iso-kit.mjs";
import * as G from "../kit/lathe.mjs";
import * as A from "../kit/audit.mjs";
import { turning } from "../kit/turn-build.mjs";
import * as TA from "../kit/turn-audit.mjs";
import { turnScript } from "../scripts/inline-kit.mjs";
import { FLYER_PER_WHEEL, OVERALL_DRAFT, SPINDLES, ROLLER_RATIO } from "./model.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const theme = argv.includes("--light") ? "light" : "dark";

const WIDTH = 720;
const HEIGHT = 500;
const AZIMUTH = 38;
const ELEVATION = 30;

const BASE = { x: -110, y: -70, w: 220, d: 140, r: 8 };
const BASE_H = 10;
const FOOT_H = 5;
const DECK = { x: -98, y: -58, w: 196, d: 116, r: 5 };
const DECK_Z = 2;

const WHEEL_X = -62;
const WHEEL_Y = 0;
const WHEEL_R = 26;
const WHEEL_HUB = 6;
const BUCKETS = 14;
const HUB_Z = DECK_Z + 42; // clears deck: HUB_Z - R - bucket ≈ 14 > race floor
const WHEEL_THICK = 7;

const HEAD_X = 18;
const HEAD_Y = -8;
const HEAD = { x: HEAD_X - 28, y: HEAD_Y - 18, w: 56, d: 52, r: 3 };
const HEAD_Z0 = 18;
const HEAD_Z1 = 22;
const ROLLER_YS = [-10, 0, 10];
const ROLLER_Z = 28;
const ROLLER_LEN = 22;
const ROLLER_R = [3.2, 2.8, 2.4];

const SPINDLE_XS = Array.from({ length: SPINDLES }, (_, i) => 42 + i * 14);
const SPINDLE_Y = 28;
const SPINDLE_Z0 = 4;
const FLYER_R = 5.5;
const FLYER_H = 14;

export const P = k.fitProjection(
  [...k.boxCorners(BASE, -BASE_H - FOOT_H, 0), [WHEEL_X, WHEEL_Y, HUB_Z + WHEEL_R + 8], [SPINDLE_XS[SPINDLES - 1] + 8, SPINDLE_Y + 10, FLYER_H + 10]],
  WIDTH,
  HEIGHT,
  { pad: 20, azimuth: AZIMUTH, elevation: ELEVATION },
);
const at = (p) => k.iso(p, P);
const S = (paths, style) => k.solidSvg(paths, style);
const L = (d, style) => k.lineSvg(d, style);
const D = (points, style) => k.dotsSvg(points, style);
const VERT = (x, y) => G.frameOf([x, y, 0], [0, 0, 1], [1, 0, 0], [0, 1, 0]);
const HORIZ_X = (x, y, z) => G.frameOf([x, y, z], [1, 0, 0], [0, 0, 1], [0, 1, 0]);
const byDepth = (points) => [...points].sort((a, b) => k.depthOf([a[0], a[1], 0], P) - k.depthOf([b[0], b[1], 0], P));

export const R = A.recorder(P);
const put = (item) =>
  R.put({
    ...item,
    shapes: item.shapes.map((shape, index) => R.solid(Object.assign(shape, { name: shape.name ?? (index ? `${item.name}#${index + 1}` : item.name) }))),
  });

function footPlate() {
  for (const [x, y] of k.corners(BASE, 18)) {
    const svg =
      S(k.cylinder(x, y, 6.5, -BASE_H - FOOT_H, 1.5, P, 24), { tone: "lo" }) +
      S(k.cylinder(x, y, 5, -BASE_H - FOOT_H + 1.5, FOOT_H - 1.5, P, 24), { tone: "mid" });
    put({
      name: `base.foot.${x}.${y}`,
      layer: "back",
      at: [x, y, -BASE_H - FOOT_H],
      svg,
      shapes: [A.cylinder(x, y, 6.5, -BASE_H - FOOT_H, 1.5, { ground: true }), A.cylinder(x, y, 5, -BASE_H - FOOT_H + 1.5, FOOT_H - 1.5)],
    });
  }
  const screws = k.corners(BASE, 8);
  const svg =
    S(k.slabOf(BASE, -BASE_H, BASE_H, P, 8, 1.4), { tone: "mid", inner: L(k.sideSeam(BASE, -BASE_H + 4, P, 8), { tone: "faint" }) }) +
    L(screws.map(([x, y]) => k.ring(x, y, 2, 0, P, 14)).join(""), { tone: "lo" }) +
    D(
      screws.map(([x, y]) => at([x, y, 0])),
      { size: 0.45 },
    );
  put({ name: "base.plate", layer: "back", at: [0, 0, -BASE_H], bias: 4, svg, shapes: [A.slab(BASE, -BASE_H, BASE_H, { ground: true })] });
}

function deck() {
  const screws = k.corners(DECK, 10);
  const groove = L(k.planOutline(k.insetPlan(DECK, 4), DECK_Z, P), { tone: "faint" });
  const svg =
    S(k.slabOf(DECK, 0, DECK_Z, P, 8, 1), { tone: "lo", crease: "faint" }) +
    groove +
    L(screws.map(([x, y]) => k.ring(x, y, 1.8, DECK_Z, P, 12)).join(""), { tone: "lo" }) +
    D(
      screws.map(([x, y]) => at([x, y, DECK_Z])),
      { size: 0.4 },
    );
  put({ name: "base.deck", layer: "back", at: [0, 0, 0], svg, shapes: [A.slab(DECK, 0, DECK_Z)] });

  // Race plaque beside the pulley
  const race = { x: WHEEL_X - 48, y: 22, w: 36, d: 14, r: 2 };
  const raceSvg =
    S(k.slabOf(race, DECK_Z, 2, P, 4, 0.5), { tone: "lo" }) +
    L(k.planOutline(k.insetPlan(race, 2), DECK_Z + 2, P), { tone: "faint" });
  put({ name: "race.plaque", layer: "back", at: [WHEEL_X - 30, 29, DECK_Z], svg: raceSvg, shapes: [A.slab(race, DECK_Z, 2)] });
}

function postsAndShaft() {
  const ped = { x: WHEEL_X - 10, y: WHEEL_Y - 10, w: 20, d: 20, r: 3 };
  put({
    name: "stand.pedestal",
    layer: "back",
    at: [WHEEL_X, WHEEL_Y, DECK_Z],
    svg: S(k.slabOf(ped, DECK_Z, 4, P, 4, 0.5), { tone: "mid" }) + S(k.cylinder(WHEEL_X, WHEEL_Y, 5, DECK_Z + 4, 2, P, 20), { tone: "lo" }),
    shapes: [A.slab(ped, DECK_Z, 4), A.cylinder(WHEEL_X, WHEEL_Y, 5, DECK_Z + 4, 2)],
  });

  // Headstock posts
  for (const [x, y] of byDepth([
    [HEAD.x + 4, HEAD.y + 4],
    [HEAD.x + HEAD.w - 4, HEAD.y + 4],
    [HEAD.x + 4, HEAD.y + HEAD.d - 4],
    [HEAD.x + HEAD.w - 4, HEAD.y + HEAD.d - 4],
  ])) {
    put({
      name: `head.post.${x}.${y}`,
      layer: "mid",
      at: [x, y, DECK_Z],
      svg: S(k.cylinder(x, y, 3, DECK_Z, HEAD_Z0 - DECK_Z, P, 20), { tone: "mid", crease: "none" }),
      shapes: [A.cylinder(x, y, 3, DECK_Z, HEAD_Z0 - DECK_Z)],
    });
  }

  // Head plate
  const hs = k.corners(HEAD, 6);
  const headSvg =
    S(k.slabOf(HEAD, HEAD_Z0, HEAD_Z1 - HEAD_Z0, P, 6, 0.9), { tone: "mid" }) +
    L(k.planOutline(k.insetPlan(HEAD, 3), HEAD_Z1, P), { tone: "faint" }) +
    L(hs.map(([x, y]) => k.ring(x, y, 1.6, HEAD_Z1, P, 12)).join(""), { tone: "lo" }) +
    D(
      hs.map(([x, y]) => at([x, y, HEAD_Z1])),
      { size: 0.4 },
    );
  put({ name: "head.plate", layer: "mid", at: [HEAD_X, HEAD_Y, HEAD_Z0], svg: headSvg, shapes: [A.slab(HEAD, HEAD_Z0, HEAD_Z1 - HEAD_Z0)] });

  // Deadweight hangers over rollers (lead weights)
  for (let i = 0; i < 3; i++) {
    const x = HEAD_X - 8 + i * 8;
    const y = HEAD_Y - 22;
    put({
      name: `head.weight.${i}`,
      layer: "mid",
      at: [x, y, HEAD_Z1],
      svg:
        S(k.cylinder(x, y, 0.7, HEAD_Z1, 6, P, 12), { tone: "lo" }) +
        S(k.cylinder(x, y, 2.8, HEAD_Z1 + 6, 4, P, 16), { tone: "hi" }) +
        L(k.ring(x, y, 1.4, HEAD_Z1 + 10, P, 12), { tone: "lo" }),
      shapes: [A.cylinder(x, y, 0.7, HEAD_Z1, 6), A.cylinder(x, y, 2.8, HEAD_Z1 + 6, 4)],
    });
  }

  // Label plate on deck
  const label = { x: 55, y: -48, w: 36, d: 12, r: 1.5 };
  const labelSvg =
    S(k.slabOf(label, DECK_Z, 1.2, P, 4, 0.4), { tone: "hi" }) +
    L(
      [
        k.pathOf([at([label.x + 3, label.y + 3, DECK_Z + 1.2]), at([label.x + label.w - 3, label.y + 3, DECK_Z + 1.2])]),
        k.pathOf([at([label.x + 3, label.y + 6, DECK_Z + 1.2]), at([label.x + label.w - 8, label.y + 6, DECK_Z + 1.2])]),
        k.pathOf([at([label.x + 3, label.y + 9, DECK_Z + 1.2]), at([label.x + label.w - 12, label.y + 9, DECK_Z + 1.2])]),
      ].join(""),
      { tone: "mid" },
    );
  put({ name: "deck.label", layer: "back", at: [72, -42, DECK_Z], svg: labelSvg, shapes: [A.slab(label, DECK_Z, 1.2)] });
}

function spindleStands() {
  // Bobbin rail base (lifts historically via heart cam — shown as a rail)
  const rail = { x: SPINDLE_XS[0] - 8, y: SPINDLE_Y - 8, w: SPINDLE_XS[SPINDLES - 1] - SPINDLE_XS[0] + 16, d: 16, r: 2 };
  put({
    name: "spindle.rail",
    layer: "back",
    at: [SPINDLE_XS[0], SPINDLE_Y, SPINDLE_Z0],
    svg: S(k.slabOf(rail, SPINDLE_Z0, 3, P, 4, 0.5), { tone: "mid" }) + L(k.planOutline(k.insetPlan(rail, 2), SPINDLE_Z0 + 3, P), { tone: "faint" }),
    shapes: [A.slab(rail, SPINDLE_Z0, 3)],
  });
  for (const x of SPINDLE_XS) {
    put({
      name: `spindle.bush.${x}`,
      layer: "mid",
      at: [x, SPINDLE_Y, SPINDLE_Z0 + 3],
      svg: S(k.cylinder(x, SPINDLE_Y, 2.4, SPINDLE_Z0 + 3, 2, P, 16), { tone: "lo" }),
      shapes: [A.cylinder(x, SPINDLE_Y, 2.4, SPINDLE_Z0 + 3, 2)],
    });
  }
}

export const T = turning(P, { recorder: R });
// Drive pulley / water-wheel stand-in on the countershaft — one 3D turn subject.
const wheel = T.group("wheel", { turn: { pivot: [WHEEL_X, WHEEL_Y] } });
const live = T.layer("wheel");
T.stack(["back", "wheel", "mid", "front"]);

export const follow = (values) => ({ ...values, wheel: values.wheel ?? 0 });
export const poses = () => Array.from({ length: 72 }, (_, i) => follow({ wheel: i * 5 }));

const AXIS_Z = VERT(WHEEL_X, WHEEL_Y);
const W = { group: wheel, layer: live, material: "gunmetal" };
const DISK_Z0 = DECK_Z + 6;
const DISK_Z1 = DECK_Z + 18;
const HUB_TOP = DISK_Z1 + 5;

// One solid disk (no concentric interlocks) + hub boss on top + buckets on the rim face
T.round({
  name: "wheel.disk",
  ...W,
  F: AXIS_Z,
  s0: DISK_Z0,
  s1: DISK_Z1,
  r: WHEEL_R,
  tone: "hi",
  crease: "lo",
  material: "gunmetal",
  details: {
    ribs: { s0: DISK_Z0 + 0.7, s1: DISK_Z1 - 0.7, count: 80, seams: true, tone: "lo", fade: [0.08, 0.5] },
    seams: [(DISK_Z0 + DISK_Z1) / 2],
  },
});
T.round({
  name: "wheel.hub",
  ...W,
  F: AXIS_Z,
  s0: DISK_Z1,
  s1: HUB_TOP,
  r: WHEEL_HUB,
  tone: "hi",
  crease: "lo",
  material: "steel",
  details: { bolts: [{ s: HUB_TOP, r: 3.6, count: 6, size: 0.42 }] },
});
T.round({
  name: "wheel.drum",
  ...W,
  F: AXIS_Z,
  s0: HUB_TOP,
  s1: HUB_TOP + 3.5,
  r: 9,
  tone: "mid",
  material: "brass",
  details: { ribs: { s0: HUB_TOP + 0.4, s1: HUB_TOP + 3.1, count: 28, seams: true, tone: "lo" } },
});

for (let i = 0; i < BUCKETS; i++) {
  const a = (i / BUCKETS) * Math.PI * 2;
  const cx = WHEEL_X + Math.cos(a) * (WHEEL_R - 2.4);
  const cy = WHEEL_Y + Math.sin(a) * (WHEEL_R - 2.4);
  const ux = Math.cos(a);
  const uy = Math.sin(a);
  const tx = -uy;
  const ty = ux;
  const poly = [
    [cx + tx * 2.2, cy + ty * 2.2],
    [cx + ux * 3.0 + tx * 2.2, cy + uy * 3.0 + ty * 2.2],
    [cx + ux * 3.0 - tx * 2.2, cy + uy * 3.0 - ty * 2.2],
    [cx - tx * 2.2, cy - ty * 2.2],
  ];
  T.prism({
    name: `wheel.bucket.${i}`,
    group: wheel,
    layer: live,
    F: { o: [0, 0, 0], a: [0, 0, 1], u: [1, 0, 0], v: [0, 1, 0] },
    polygon: poly,
    s0: DISK_Z1,
    s1: DISK_Z1 + 3.0,
    bevel: 0.2,
    tone: "mid",
    material: "gunmetal",
  });
}


function driveTrain() {
  // Intermediate belt drums and a gear train from the pulley to the head
  for (const [name, x, y, r, h0, h] of [
    ["belt.idler.0", WHEEL_X + 28, -18, 5, DECK_Z + 8, 6],
    ["belt.idler.1", WHEEL_X + 46, -6, 4.2, DECK_Z + 10, 5],
    ["belt.idler.2", HEAD_X - 34, HEAD_Y + 6, 4.8, DECK_Z + 12, 6],
  ]) {
    put({
      name,
      layer: "mid",
      at: [x, y, h0],
      svg:
        S(k.cylinder(x, y, r, h0, h, P, 20), { tone: "mid" }) +
        S(k.cylinder(x, y, r * 0.45, h0 + h, 2, P, 14), { tone: "lo" }) +
        L(k.ring(x, y, r - 0.4, h0 + h, P, 20), { tone: "lo" }),
      shapes: [A.cylinder(x, y, r, h0, h)],
    });
  }
  // Crown gear on the head vertical shaft
  put({
    name: "head.crown",
    layer: "mid",
    at: [HEAD_X - 30, HEAD_Y + 6, HEAD_Z1],
    svg:
      S(k.cylinder(HEAD_X - 30, HEAD_Y + 6, 7, HEAD_Z1, 3.5, P, 24), { tone: "hi" }) +
      L(Array.from({ length: 16 }, (_, j) => {
        const a = (j / 16) * Math.PI * 2;
        const x = HEAD_X - 30 + Math.cos(a) * 6.2;
        const y = HEAD_Y + 6 + Math.sin(a) * 6.2;
        return k.ring(x, y, 0.7, HEAD_Z1 + 3.5, P, 8);
      }).join(""), { tone: "lo" }),
    shapes: [A.cylinder(HEAD_X - 30, HEAD_Y + 6, 7, HEAD_Z1, 3.5)],
  });
  // Vertical drive shaft
  put({
    name: "head.vshaft",
    layer: "mid",
    at: [HEAD_X - 30, HEAD_Y + 6, DECK_Z],
    svg: S(k.cylinder(HEAD_X - 30, HEAD_Y + 6, 1.6, DECK_Z + 4, HEAD_Z1 - DECK_Z - 4, P, 14), { tone: "mid" }),
    shapes: [A.cylinder(HEAD_X - 30, HEAD_Y + 6, 1.6, DECK_Z + 4, HEAD_Z1 - DECK_Z - 4)],
  });
  // Guide eyes from rollers to flyers
  for (let i = 0; i < SPINDLES; i++) {
    const x = SPINDLE_XS[i];
    put({
      name: `guide.eye.${i}`,
      layer: "mid",
      at: [x, SPINDLE_Y - 14, ROLLER_Z],
      svg:
        S(k.cylinder(x, SPINDLE_Y - 14, 1.8, ROLLER_Z - 1, 2.5, P, 12), { tone: "lo" }) +
        L(k.ring(x, SPINDLE_Y - 14, 1.1, ROLLER_Z + 1.5, P, 12), { tone: "mid" }),
      shapes: [A.cylinder(x, SPINDLE_Y - 14, 1.8, ROLLER_Z - 1, 2.5)],
    });
  }
  // Heart-cam for bobbin traverse (static)
  put({
    name: "cam.heart",
    layer: "mid",
    at: [SPINDLE_XS[0] - 16, SPINDLE_Y + 10, DECK_Z + 4],
    svg:
      S(k.cylinder(SPINDLE_XS[0] - 16, SPINDLE_Y + 10, 4.5, DECK_Z + 4, 3, P, 20), { tone: "hi" }) +
      S(k.cylinder(SPINDLE_XS[0] - 16, SPINDLE_Y + 10, 1.2, DECK_Z + 7, 2, P, 12), { tone: "lo" }),
    shapes: [A.cylinder(SPINDLE_XS[0] - 16, SPINDLE_Y + 10, 4.5, DECK_Z + 4, 3)],
  });
  // Floor ruler strip
  const rule = { x: -90, y: 48, w: 120, d: 4, r: 0.5 };
  put({
    name: "deck.ruler",
    layer: "back",
    at: [-30, 50, DECK_Z],
    svg:
      S(k.slabOf(rule, DECK_Z, 0.8, P, 2, 0.2), { tone: "hi" }) +
      L(Array.from({ length: 25 }, (_, j) => {
        const x = rule.x + 4 + j * 4.5;
        const len = j % 5 === 0 ? 3.2 : 1.8;
        return k.pathOf([at([x, rule.y + 0.4, DECK_Z + 0.8]), at([x, rule.y + len, DECK_Z + 0.8])]);
      }).join(""), { tone: "mid" }),
    shapes: [A.slab(rule, DECK_Z, 0.8)],
  });
}

function draftingHead() {
  // Three roller pairs — static, sizes encode ratio 1 : 1.6 : 18.4
  for (let i = 0; i < 3; i++) {
    const y = ROLLER_YS[i];
    const r = ROLLER_R[i];
    const z = ROLLER_Z;
    const x0 = HEAD_X - ROLLER_LEN / 2;
    // Approximate horizontal rollers as short stacked cylinders along y-depth for kit simplicity
    put({
      name: `roller.bottom.${i}`,
      layer: "mid",
      at: [HEAD_X, y, z],
      svg:
        S(k.cylinder(HEAD_X - 6, y, r, z - r, r * 2, P, 20), { tone: "hi" }) +
        S(k.cylinder(HEAD_X, y, r, z - r, r * 2, P, 20), { tone: "hi" }) +
        S(k.cylinder(HEAD_X + 6, y, r, z - r, r * 2, P, 20), { tone: "hi" }) +
        L(k.ring(HEAD_X, y, r + 0.3, z + r, P, 20), { tone: "lo" }),
      shapes: [A.cylinder(HEAD_X, y, r, z - r, r * 2)],
    });
    const tr = ROLLER_R[i] * 0.85;
    const tz = z + r + tr + 0.3;
    put({
      name: `roller.top.${i}`,
      layer: "mid",
      at: [HEAD_X, y, tz],
      svg:
        S(k.cylinder(HEAD_X - 5, y, tr, tz - tr, tr * 2, P, 18), { tone: "mid" }) +
        S(k.cylinder(HEAD_X + 5, y, tr, tz - tr, tr * 2, P, 18), { tone: "mid" }),
      shapes: [A.cylinder(HEAD_X, y, tr, tz - tr, tr * 2)],
    });
    void x0;
  }

  for (let i = 0; i < SPINDLES; i++) {
    const x = SPINDLE_XS[i];
    const lit = i === 1;
    const armZ = SPINDLE_Z0 + 5 + FLYER_H - 1;
    const body =
      S(k.cylinder(x, SPINDLE_Y, 1.1, SPINDLE_Z0 + 5, FLYER_H, P, 16), { tone: "hi", lit }) +
      S(k.cylinder(x, SPINDLE_Y, 3.2, SPINDLE_Z0 + 6, 8, P, 18), { tone: "mid" }) +
      S(k.cylinder(x + FLYER_R, SPINDLE_Y, 0.55, SPINDLE_Z0 + 8, armZ - (SPINDLE_Z0 + 8), P, 12), { tone: "mid" }) +
      S(k.cylinder(x - FLYER_R, SPINDLE_Y, 0.55, SPINDLE_Z0 + 8, armZ - (SPINDLE_Z0 + 8), P, 12), { tone: "mid" }) +
      S(k.cylinder(x + FLYER_R, SPINDLE_Y, 1.2, SPINDLE_Z0 + 8, 1.2, P, 12), { tone: lit ? "hi" : "lo", lit }) +
      L(k.ring(x, SPINDLE_Y, FLYER_R, armZ, P, 24), { tone: lit ? "hi" : "mid" });
    put({
      name: `flyer.${i}`,
      layer: "mid",
      at: [x, SPINDLE_Y, SPINDLE_Z0 + 5],
      svg: body,
      shapes: [
        A.cylinder(x, SPINDLE_Y, 1.1, SPINDLE_Z0 + 5, FLYER_H),
        A.cylinder(x, SPINDLE_Y, 3.2, SPINDLE_Z0 + 6, 8),
      ],
    });
  }

  for (let i = 0; i < 3; i++) {
    const x = HEAD_X - 18 + i * 10;
    const y = HEAD_Y - 30;
    put({
      name: `creel.bobbin.${i}`,
      layer: "mid",
      at: [x, y, HEAD_Z1],
      svg: S(k.cylinder(x, y, 1, HEAD_Z1, 10, P, 12), { tone: "lo" }) + S(k.cylinder(x, y, 3.2, HEAD_Z1 + 2, 7, P, 16), { tone: "mid" }),
      shapes: [A.cylinder(x, y, 1, HEAD_Z1, 10), A.cylinder(x, y, 3.2, HEAD_Z1 + 2, 7)],
    });
  }
}

footPlate();
deck();
postsAndShaft();
spindleStands();
driveTrain();
draftingHead();

const verify = argv.includes("--verify");
const out = T.build({ statics: R.items, poses, verify, strict: !argv.includes("--loose") });
A.settle(R, P);

const layerOf = (name) =>
  R.items
    .filter((item) => item.layer === name)
    .sort((a, b) => a.key - b.key)
    .map((item) => item.svg);

if (argv.includes("--audit")) {
  A.auditOrExit(R, P);
  TA.orbitOrExit(T, R, P, {
    sweep: { at: (x) => follow({ wheel: x }), from: 0, to: 360, frame: 0.5 },
    clips: [],
    quick: argv.includes("--quick"),
    only: argv.find((a) => a.startsWith("--only="))?.slice(7).split(",") ?? null,
  });
}

const LABEL = `Arkwright water frame: continuous drafting through three roller pairs at ratios ${ROLLER_RATIO.join(":")} (overall draft ${OVERALL_DRAFT}×), then flyer twist onto bobbins. The water wheel is the drive.`;
const BACK = [`<path class="iso-halo" d="${k.haloOf(BASE, -BASE_H - FOOT_H, BASE_H, P)}"/>`, ...layerOf("back")];
const MID = layerOf("mid");
const FRONT = layerOf("front");
const backSvg = k.figureSvg({ width: WIDTH, height: HEIGHT, label: LABEL, body: BACK });
const staticSvg = (list) => `<svg xmlns="http://www.w3.org/2000/svg" class="iso-svg iso-layer" viewBox="0 0 ${WIDTH} ${HEIGHT}" aria-hidden="true">${list.join("")}</svg>`;
const stage = `<div class="iso-stage iso-turn wf-stage" tabindex="0" role="slider" aria-label="Water frame: drag the water wheel or press Space to run" aria-valuemin="0" aria-valuemax="360" aria-valuenow="0" aria-valuetext="wheel at 0 degrees">${backSvg}${out.layerSvg("wheel", { width: WIDTH, height: HEIGHT })}${staticSvg(MID)}${staticSvg(FRONT)}</div>`;

const DATA = {
  turn: out.data,
  wheel: [WHEEL_X, WHEEL_Y, DECK_Z + 24],
  draft: OVERALL_DRAFT,
  ratios: [...ROLLER_RATIO],
  flyerPerWheel: FLYER_PER_WHEEL,
};
const FOLLOW = `const follow = ${follow.toString()};`;
const CSS = out.css + "\n" + readFileSync(join(HERE, "water-frame.css"), "utf8");
const LIVE = readFileSync(join(HERE, "live.js"), "utf8").replace("__DATA__", JSON.stringify(DATA)).replace("const follow = null;", FOLLOW);
const body = k.plateHtml({
  fig: "Fig WF",
  title: "Water frame",
  hint: "Drag the drive pulley · Space run · S slow",
  readout: "wheel 0° · draft 18.4× · twist — · idle",
  keys: [
    { mark: "raised", label: "Water wheel: continuous power" },
    { mark: "lit", label: "Flyer heck: twist enters the yarn" },
  ],
  caption: `Roller speeds ${ROLLER_RATIO.join(" : ")} (Science Museum 1775 machine). Overall draft ${OVERALL_DRAFT}×. Flyer lag winds the bobbin while the heck inserts one turn of twist per revolution — continuous warp yarn.`,
  body: `<style>${CSS}</style>${stage}`,
});
const page = k.pageHtml({
  title: "Water frame — Anatomy",
  theme,
  body,
  script: turnScript() + (verify ? `window.__isoVerify = ${JSON.stringify(out.verify)};\n` : "") + LIVE,
  width: 760,
});

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const name = `water-frame${verify ? "-verify" : ""}${theme === "light" ? "-light" : ""}.html`;
  writeFileSync(join(HERE, name), page);
  console.log(`wrote ${name} · ${(page.length / 1024).toFixed(0)} KB · ${out.report.parts} parts · build ${out.report.seconds.toFixed(1)} s`);
}

export { out };
