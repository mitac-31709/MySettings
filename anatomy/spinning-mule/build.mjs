/**
 * Spinning mule (Crompton, 1779) — Hero, 3D.
 * The object is intermittent draft+twist on a sliding carriage, then wind-on return.
 * Drag the carriage / Space to cycle. Readout comes from model.mjs.
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
import { DRAW_M, SPINDLES, TRAVEL, TWIST_ON_DRAW } from "./model.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const theme = argv.includes("--light") ? "light" : "dark";

const WIDTH = 760;
const HEIGHT = 500;
const AZIMUTH = 42;
const ELEVATION = 28;

const BASE = { x: -120, y: -64, w: 240, d: 128, r: 8 };
const BASE_H = 10;
const FOOT_H = 5;
const DECK = { x: -110, y: -52, w: 220, d: 104, r: 5 };
const DECK_Z = 2;

const HEAD_X = -70;
const HEAD_Y = 0;
const HEAD = { x: HEAD_X - 22, y: HEAD_Y - 28, w: 44, d: 56, r: 3 };
const HEAD_Z0 = 16;
const HEAD_Z1 = 20;
const ROLLER_Z = 26;

const CAR_Y0 = -22;
const CAR_REST_X = -18;
const CAR_W = 70;
const CAR_D = 44;
const CAR_Z = DECK_Z + 3;
const SPINDLE_YS = Array.from({ length: SPINDLES }, (_, i) => CAR_Y0 + 6 + i * 6);
const SPINDLE_LOCAL_X = 22;

export const P = k.fitProjection(
  [
    ...k.boxCorners(BASE, -BASE_H - FOOT_H, 0),
    [CAR_REST_X + TRAVEL + CAR_W, CAR_Y0 + CAR_D, 36],
    [HEAD_X - 30, HEAD_Y - 36, 40],
  ],
  WIDTH,
  HEIGHT,
  { pad: 18, azimuth: AZIMUTH, elevation: ELEVATION },
);
const at = (p) => k.iso(p, P);
const S = (paths, style) => k.solidSvg(paths, style);
const L = (d, style) => k.lineSvg(d, style);
const D = (points, style) => k.dotsSvg(points, style);
const VERT = (x, y) => G.frameOf([x, y, 0], [0, 0, 1], [1, 0, 0], [0, 1, 0]);
const byDepth = (points) => [...points].sort((a, b) => k.depthOf([a[0], a[1], 0], P) - k.depthOf([b[0], b[1], 0], P));

export const R = A.recorder(P);
const put = (item) =>
  R.put({
    ...item,
    shapes: item.shapes.map((shape, index) => R.solid(Object.assign(shape, { name: shape.name ?? (index ? `${item.name}#${index + 1}` : item.name) }))),
  });

function footPlate() {
  for (const [x, y] of k.corners(BASE, 18)) {
    put({
      name: `base.foot.${x}.${y}`,
      layer: "back",
      at: [x, y, -BASE_H - FOOT_H],
      svg: S(k.cylinder(x, y, 6.5, -BASE_H - FOOT_H, 1.5, P, 24), { tone: "lo" }) + S(k.cylinder(x, y, 5, -BASE_H - FOOT_H + 1.5, FOOT_H - 1.5, P, 24), { tone: "mid" }),
      shapes: [A.cylinder(x, y, 6.5, -BASE_H - FOOT_H, 1.5, { ground: true }), A.cylinder(x, y, 5, -BASE_H - FOOT_H + 1.5, FOOT_H - 1.5)],
    });
  }
  const screws = k.corners(BASE, 8);
  put({
    name: "base.plate",
    layer: "back",
    at: [0, 0, -BASE_H],
    bias: 4,
    svg:
      S(k.slabOf(BASE, -BASE_H, BASE_H, P, 8, 1.4), { tone: "mid", inner: L(k.sideSeam(BASE, -BASE_H + 4, P, 8), { tone: "faint" }) }) +
      L(screws.map(([x, y]) => k.ring(x, y, 2, 0, P, 14)).join(""), { tone: "lo" }) +
      D(
        screws.map(([x, y]) => at([x, y, 0])),
        { size: 0.45 },
      ),
    shapes: [A.slab(BASE, -BASE_H, BASE_H, { ground: true })],
  });
}

function deck() {
  const screws = k.corners(DECK, 10);
  put({
    name: "base.deck",
    layer: "back",
    at: [0, 0, 0],
    svg:
      S(k.slabOf(DECK, 0, DECK_Z, P, 8, 1), { tone: "lo", crease: "faint" }) +
      L(k.planOutline(k.insetPlan(DECK, 4), DECK_Z, P), { tone: "faint" }) +
      L(screws.map(([x, y]) => k.ring(x, y, 1.8, DECK_Z, P, 12)).join(""), { tone: "lo" }) +
      D(
        screws.map(([x, y]) => at([x, y, DECK_Z])),
        { size: 0.4 },
      ),
    shapes: [A.slab(DECK, 0, DECK_Z)],
  });

  // Carriage rails (two ways)
  for (const [name, y] of [
    ["rail.n", CAR_Y0 - 4],
    ["rail.s", CAR_Y0 + CAR_D + 4],
  ]) {
    const rail = { x: CAR_REST_X - 8, y: y - 2, w: TRAVEL + CAR_W + 24, d: 4, r: 1 };
    put({
      name,
      layer: "back",
      at: [CAR_REST_X + TRAVEL / 2, y, DECK_Z],
      svg: S(k.slabOf(rail, DECK_Z, 2.2, P, 4, 0.4), { tone: "mid" }) + L(k.planOutline(k.insetPlan(rail, 1), DECK_Z + 2.2, P), { tone: "faint" }),
      shapes: [A.slab(rail, DECK_Z, 2.2)],
    });
  }

  // Draw scale (metres)
  const rule = { x: CAR_REST_X, y: CAR_Y0 + CAR_D + 12, w: TRAVEL, d: 3.5, r: 0.4 };
  put({
    name: "deck.scale",
    layer: "back",
    at: [CAR_REST_X + TRAVEL / 2, rule.y, DECK_Z],
    svg:
      S(k.slabOf(rule, DECK_Z, 0.7, P, 2, 0.2), { tone: "hi" }) +
      L(
        Array.from({ length: 11 }, (_, j) => {
          const x = CAR_REST_X + (j / 10) * TRAVEL;
          return k.pathOf([at([x, rule.y + 0.3, DECK_Z + 0.7]), at([x, rule.y + (j % 5 === 0 ? 3 : 1.8), DECK_Z + 0.7])]);
        }).join(""),
        { tone: "mid" },
      ),
    shapes: [A.slab(rule, DECK_Z, 0.7)],
  });
}

function headstock() {
  for (const [x, y] of byDepth([
    [HEAD.x + 4, HEAD.y + 4],
    [HEAD.x + HEAD.w - 4, HEAD.y + 4],
    [HEAD.x + 4, HEAD.y + HEAD.d - 4],
    [HEAD.x + HEAD.w - 4, HEAD.y + HEAD.d - 4],
  ])) {
    put({
      name: `head.post.${x}.${y}`,
      layer: "back",
      at: [x, y, DECK_Z],
      svg: S(k.cylinder(x, y, 3, DECK_Z, HEAD_Z0 - DECK_Z, P, 18), { tone: "mid", crease: "none" }),
      shapes: [A.cylinder(x, y, 3, DECK_Z, HEAD_Z0 - DECK_Z)],
    });
  }
  const hs = k.corners(HEAD, 6);
  put({
    name: "head.plate",
    layer: "back",
    at: [HEAD_X, HEAD_Y, HEAD_Z0],
    svg:
      S(k.slabOf(HEAD, HEAD_Z0, HEAD_Z1 - HEAD_Z0, P, 6, 0.9), { tone: "mid" }) +
      L(k.planOutline(k.insetPlan(HEAD, 3), HEAD_Z1, P), { tone: "faint" }) +
      L(hs.map(([x, y]) => k.ring(x, y, 1.6, HEAD_Z1, P, 12)).join(""), { tone: "lo" }) +
      D(
        hs.map(([x, y]) => at([x, y, HEAD_Z1])),
        { size: 0.4 },
      ),
    shapes: [A.slab(HEAD, HEAD_Z0, HEAD_Z1 - HEAD_Z0)],
  });

  // Three drafting roller pairs (static)
  for (let i = 0; i < 3; i++) {
    const y = HEAD_Y - 12 + i * 12;
    const r = 2.8 - i * 0.25;
    put({
      name: `head.roller.${i}`,
      layer: "back",
      at: [HEAD_X, y, ROLLER_Z],
      svg:
        S(k.cylinder(HEAD_X - 5, y, r, ROLLER_Z - r, r * 2, P, 16), { tone: "hi" }) +
        S(k.cylinder(HEAD_X + 5, y, r, ROLLER_Z - r, r * 2, P, 16), { tone: "hi" }) +
        S(k.cylinder(HEAD_X, y, r * 0.85, ROLLER_Z + r, r * 1.6, P, 14), { tone: "mid" }),
      shapes: [A.cylinder(HEAD_X, y, r, ROLLER_Z - r, r * 2)],
    });
  }

  // Creel
  for (let i = 0; i < 4; i++) {
    const y = HEAD_Y - 18 + i * 10;
    put({
      name: `creel.${i}`,
      layer: "back",
      at: [HEAD_X - 28, y, HEAD_Z1],
      svg: S(k.cylinder(HEAD_X - 28, y, 1, HEAD_Z1, 9, P, 12), { tone: "lo" }) + S(k.cylinder(HEAD_X - 28, y, 3, HEAD_Z1 + 1.5, 6, P, 14), { tone: "mid" }),
      shapes: [A.cylinder(HEAD_X - 28, y, 1, HEAD_Z1, 9), A.cylinder(HEAD_X - 28, y, 3, HEAD_Z1 + 1.5, 6)],
    });
  }

  // Faller wire posts (static guides toward carriage)
  for (const y of [-16, 16]) {
    put({
      name: `faller.post.${y}`,
      layer: "back",
      at: [HEAD_X + 26, y, DECK_Z],
      svg: S(k.cylinder(HEAD_X + 26, y, 1.4, DECK_Z, 22, P, 12), { tone: "mid" }) + S(k.cylinder(HEAD_X + 26, y, 2.2, DECK_Z + 20, 2, P, 12), { tone: "lo" }),
      shapes: [A.cylinder(HEAD_X + 26, y, 1.4, DECK_Z, 22)],
    });
  }

  const label = { x: -108, y: -48, w: 32, d: 10, r: 1.2 };
  put({
    name: "deck.label",
    layer: "back",
    at: [-92, -43, DECK_Z],
    svg:
      S(k.slabOf(label, DECK_Z, 1.1, P, 4, 0.3), { tone: "hi" }) +
      L(
        [
          k.pathOf([at([label.x + 3, label.y + 3, DECK_Z + 1.1]), at([label.x + label.w - 3, label.y + 3, DECK_Z + 1.1])]),
          k.pathOf([at([label.x + 3, label.y + 6.5, DECK_Z + 1.1]), at([label.x + label.w - 8, label.y + 6.5, DECK_Z + 1.1])]),
        ].join(""),
        { tone: "mid" },
      ),
    shapes: [A.slab(label, DECK_Z, 1.1)],
  });
}

export const T = turning(P, { recorder: R });
const carriage = T.group("carriage", {
  slide: { direction: [1, 0, 0], travel: TRAVEL },
});
const live = T.layer("carriage");
T.stack(["back", "carriage", "front"]);

export const follow = (values) => ({ ...values, carriage: Math.max(0, Math.min(TRAVEL, values.carriage ?? 0)) });
export const poses = () => Array.from({ length: 57 }, (_, i) => follow({ carriage: i }));

const CAR = { x: CAR_REST_X, y: CAR_Y0, w: CAR_W, d: CAR_D, r: 2.5 };
const C = { group: carriage, layer: live };

T.prism({
  name: "carriage.bed",
  ...C,
  plan: CAR,
  z: CAR_Z,
  h: 4,
  steps: 3,
  bevel: 0.6,
  tone: "hi",
  crease: "lo",
  material: "gunmetal",
  details: {
    seams: [CAR_Z + 2],
    dots: k.corners(CAR, 6).map(([x, y]) => ({ at: [CAR_Z + 4, x, y], normal: [0, 0, 1], size: 0.42, tone: "mid" })),
  },
});

// Wheel trucks
for (const [i, x] of [CAR_REST_X + 8, CAR_REST_X + CAR_W - 8].entries()) {
  for (const [j, y] of [CAR_Y0 + 4, CAR_Y0 + CAR_D - 4].entries()) {
    T.round({
      name: `carriage.truck.${i}.${j}`,
      ...C,
      F: VERT(x, y),
      s0: DECK_Z + 2.2,
      s1: CAR_Z,
      r: 2.4,
      tone: "mid",
      material: "steel",
      details: { seams: [DECK_Z + 3.5] },
    });
  }
}

// Spindle rail on carriage
const railPlan = { x: CAR_REST_X + SPINDLE_LOCAL_X - 6, y: CAR_Y0 + 2, w: 12, d: CAR_D - 4, r: 1.5 };
T.prism({
  name: "carriage.spindleRail",
  ...C,
  plan: railPlan,
  z: CAR_Z + 4,
  h: 3,
  bevel: 0.35,
  tone: "mid",
  material: "brass",
  details: { seams: [CAR_Z + 5.5] },
});

// Spindles + cops — stacked without concentric interlock
for (let i = 0; i < SPINDLES; i++) {
  const x = CAR_REST_X + SPINDLE_LOCAL_X;
  const y = SPINDLE_YS[i];
  const lit = i === 2 || i === 3;
  const z0 = CAR_Z + 7;
  T.round({
    name: `carriage.whorl.${i}`,
    ...C,
    F: VERT(x, y),
    s0: z0,
    s1: z0 + 1.8,
    r: 2.2,
    tone: "lo",
    material: "gunmetal",
  });
  T.round({
    name: `carriage.cop.${i}`,
    ...C,
    F: VERT(x, y),
    s0: z0 + 1.8,
    s1: z0 + 12,
    r: [2.8, 1.8],
    tone: "mid",
    material: "brass",
    details: { seams: [z0 + 5, z0 + 9] },
  });
  T.round({
    name: `carriage.spindle.${i}`,
    ...C,
    F: VERT(x, y),
    s0: z0 + 12,
    s1: z0 + 18,
    r: 0.85,
    tone: "hi",
    material: "chrome",
    lit,
  });
}

// Carriage handle / quadrant (control)
T.prism({
  name: "carriage.handle.base",
  ...C,
  plan: { x: CAR_REST_X + 4, y: CAR_Y0 + CAR_D / 2 - 4, w: 10, d: 8, r: 1.2 },
  z: CAR_Z + 4,
  h: 6,
  bevel: 0.3,
  tone: "mid",
  material: "steel",
});
T.round({
  name: "carriage.handle",
  ...C,
  F: VERT(CAR_REST_X + 9, CAR_Y0 + CAR_D / 2),
  s0: CAR_Z + 10,
  s1: CAR_Z + 18,
  r: 1.3,
  tone: "hi",
  material: "chrome",
  lit: true,
  details: { bolts: [{ s: CAR_Z + 18, r: 0, count: 1, size: 0.4 }] },
});

// End stops (static, in front layer so they sit over the travel)
for (const [name, x, layer] of [
  ["stop.home", CAR_REST_X - 6, "back"],
  ["stop.out", CAR_REST_X + TRAVEL + CAR_W + 2, "front"],
]) {
  put({
    name,
    layer,
    at: [x, CAR_Y0 + CAR_D / 2, DECK_Z],
    svg: S(k.slabOf({ x: x - 2, y: CAR_Y0 + 8, w: 4, d: CAR_D - 16, r: 1 }, DECK_Z, 8, P, 3, 0.4), { tone: "lo" }),
    shapes: [A.slab({ x: x - 2, y: CAR_Y0 + 8, w: 4, d: CAR_D - 16, r: 1 }, DECK_Z, 8)],
  });
}

footPlate();
deck();
headstock();

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
    sweep: { at: (x) => follow({ carriage: x }), from: 0, to: TRAVEL, frame: 0.5 },
    clips: [],
    quick: argv.includes("--quick"),
    only: argv.find((a) => a.startsWith("--only="))?.slice(7).split(",") ?? null,
  });
}

const LABEL = `Crompton spinning mule: carriage draws out ${DRAW_M} m while spindles twist (${TWIST_ON_DRAW} turns), then returns winding yarn onto the cops — intermittent, unlike the water frame.`;
const BACK = [`<path class="iso-halo" d="${k.haloOf(BASE, -BASE_H - FOOT_H, BASE_H, P)}"/>`, ...layerOf("back")];
const FRONT = layerOf("front");
const backSvg = k.figureSvg({ width: WIDTH, height: HEIGHT, label: LABEL, body: BACK });
const staticSvg = (list) => `<svg xmlns="http://www.w3.org/2000/svg" class="iso-svg iso-layer" viewBox="0 0 ${WIDTH} ${HEIGHT}" aria-hidden="true">${list.join("")}</svg>`;
const stage = `<div class="iso-stage iso-turn mule-stage" tabindex="0" role="slider" aria-label="Spinning mule: drag the carriage or press Space to run a draw-and-wind cycle" aria-valuemin="0" aria-valuemax="${TRAVEL}" aria-valuenow="0" aria-valuetext="carriage at home">${backSvg}${out.layerSvg("carriage", { width: WIDTH, height: HEIGHT })}${staticSvg(FRONT)}</div>`;

const DATA = { turn: out.data, travel: TRAVEL, drawM: DRAW_M, twist: TWIST_ON_DRAW, spindles: SPINDLES };
const FOLLOW = `const follow = ${follow.toString()};`;
const CSS = out.css + "\n" + readFileSync(join(HERE, "mule.css"), "utf8");
const LIVE = readFileSync(join(HERE, "live.js"), "utf8").replace("__DATA__", JSON.stringify(DATA)).replace("const follow = null;", FOLLOW);
const body = k.plateHtml({
  fig: "Fig SM",
  title: "Spinning mule",
  hint: "Drag carriage · Space cycle · S slow",
  readout: "carriage 0.00 m · ready · twist 0 · idle",
  keys: [
    { mark: "raised", label: "Carriage: draws and returns" },
    { mark: "lit", label: "Spindle / handle: twist then wind" },
  ],
  caption: `Draw ${DRAW_M} m (${TRAVEL} wu). Outward = drafting + twist; return = winding. ${SPINDLES} spindles shown (Crompton's early mules had dozens).`,
  body: `<style>${CSS}</style>${stage}`,
});
const page = k.pageHtml({
  title: "Spinning mule — Anatomy",
  theme,
  body,
  script: turnScript() + (verify ? `window.__isoVerify = ${JSON.stringify(out.verify)};\n` : "") + LIVE,
  width: 800,
});

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const name = `spinning-mule${verify ? "-verify" : ""}${theme === "light" ? "-light" : ""}.html`;
  writeFileSync(join(HERE, name), page);
  console.log(`wrote ${name} · ${(page.length / 1024).toFixed(0)} KB · ${out.report.parts} parts · build ${out.report.seconds.toFixed(1)} s`);
}

export { out };
