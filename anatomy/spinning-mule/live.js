const DATA = __DATA__;
const follow = null;
const stage = document.querySelector(".mule-stage");
const readout = document.querySelector("[data-readout]");
const still = matchMedia("(prefers-reduced-motion: reduce)");

const TRAVEL = DATA.travel ?? 56;
const DRAW_M = DATA.drawM ?? 1.52;
const TWIST = DATA.twist ?? 48;

let carriage = 0;
let target = 0;
let returning = false;
let running = false;
let slow = 1;
let frame = 0;
let last = 0;
let visible = false;
let touring = !still.matches;
let idle = 0;
let dragging = false;
let own = false;

const phaseOf = (pos, ret) => {
  const u = pos / TRAVEL;
  if (ret) return u > 0.92 ? "backing-off" : "winding";
  if (u < 0.04) return "ready";
  return "drawing";
};
const twistOf = (pos, ret) => (ret ? TWIST : TWIST * (pos / TRAVEL));
const metresOf = (pos) => DRAW_M * (pos / TRAVEL);

const show = (pos, ret, run) => {
  const phase = phaseOf(pos, ret);
  const twist = twistOf(pos, ret).toFixed(0);
  const metres = metresOf(pos).toFixed(2);
  const mode = run ? "cycling" : "idle";
  const text = `carriage ${metres} m · ${phase} · twist ${twist} · ${mode}`;
  if (readout && readout.textContent !== text) readout.textContent = text;
  stage.setAttribute("aria-valuenow", String(Math.round(pos)));
  stage.setAttribute("aria-valuetext", `Spinning mule ${phase}, carriage at ${metres} metres, ${twist} turns of twist`);
};

const hold = () => {
  touring = false;
  clearTimeout(idle);
  idle = setTimeout(() => {
    if (!running && !dragging) {
      touring = !still.matches;
      run();
    }
  }, 4200);
};

const controller = TURN.mount(stage, DATA.turn, {
  follow,
  onHold: () => {
    touring = false;
    clearTimeout(idle);
  },
  onFrame: (turned) => {
    if (!own) {
      carriage = target = turned.values.carriage ?? 0;
      show(carriage, returning, running);
    }
  },
});

const apply = (pos) => {
  own = true;
  carriage = Math.max(0, Math.min(TRAVEL, pos));
  target = carriage;
  controller.set(follow({ carriage }));
  show(carriage, returning, running);
  own = false;
};

stage.addEventListener("pointerdown", (e) => {
  if (e.button !== 0) return;
  stage.setPointerCapture(e.pointerId);
  dragging = true;
  running = false;
  hold();
});
stage.addEventListener("pointermove", (e) => {
  if (!dragging) return;
  // Slide along screen X mapped into travel
  const rect = stage.getBoundingClientRect();
  const u = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
  returning = false;
  apply(u * TRAVEL);
  hold();
});
stage.addEventListener("pointerup", () => {
  dragging = false;
  hold();
});
stage.addEventListener("pointercancel", () => {
  dragging = false;
});

stage.addEventListener("keydown", (e) => {
  if (e.key === "ArrowLeft" || e.key === "ArrowRight") {
    e.preventDefault();
    running = false;
    returning = e.key === "ArrowLeft";
    apply(carriage + (e.key === "ArrowRight" ? 3 : -3) * slow);
    hold();
  } else if (e.key === " " || e.code === "Space") {
    e.preventDefault();
    running = !running;
    if (running && carriage >= TRAVEL - 0.5) returning = true;
    if (running && carriage <= 0.5) returning = false;
    hold();
    run();
  } else if (e.key === "s" || e.key === "S") {
    e.preventDefault();
    slow = slow === 1 ? 4 : slow === 4 ? 12 : 1;
    hold();
  }
});

const io = new IntersectionObserver(
  ([entry]) => {
    visible = entry.isIntersecting;
    if (visible) run();
  },
  { threshold: 0.05 },
);
io.observe(stage);

function tick(now) {
  const dt = Math.min(0.05, (now - last) / 1000 || 0);
  last = now;
  if (still.matches) {
    apply(carriage);
    frame = 0;
    return;
  }
  const speed = (28 / slow) * dt;
  if (running) {
    if (!returning) {
      apply(carriage + speed);
      if (carriage >= TRAVEL - 0.05) returning = true;
    } else {
      apply(carriage - speed * 0.85);
      if (carriage <= 0.05) {
        returning = false;
        // brief pause at home then continue if still running
      }
    }
  } else if (touring) {
    if (!returning) {
      apply(carriage + speed * 0.35);
      if (carriage >= TRAVEL - 0.05) returning = true;
    } else {
      apply(carriage - speed * 0.3);
      if (carriage <= 0.05) returning = false;
    }
  } else {
    show(carriage, returning, false);
  }
  if (visible && (running || touring || dragging)) {
    frame = requestAnimationFrame(tick);
  } else {
    frame = 0;
  }
}

function run() {
  if (frame || !visible) return;
  last = performance.now();
  frame = requestAnimationFrame(tick);
}

show(0, false, false);
apply(0);
run();
