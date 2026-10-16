const DATA = __DATA__;
const follow = null;
const stage = document.querySelector(".wf-stage");
const readout = document.querySelector("[data-readout]");
const still = matchMedia("(prefers-reduced-motion: reduce)");

const WHEEL_RPM = 12;
const FLYER_PER_WHEEL = DATA.flyerPerWheel ?? 48;
const DELIVERY_PER_WHEEL = 2.4;
const DRAFT = DATA.draft ?? 18.4;

let angle = 0;
let target = 0;
let frame = 0;
let last = 0;
let visible = false;
let touring = !still.matches;
let idle = 0;
let running = false;
let slow = 1;
let dragging = false;
let dragBase = 0;
let dragAngle = 0;
let own = false;

const flyerRpm = (rpm) => rpm * FLYER_PER_WHEEL;
const delivery = (rpm) => rpm * DELIVERY_PER_WHEEL;
const tpiOf = (rpm) => {
  const inches = delivery(Math.max(rpm, 0.001)) * 60;
  return flyerRpm(Math.max(rpm, 0.001)) / inches;
};

const show = (deg, run) => {
  const turns = ((deg % 360) + 360) % 360;
  const rpm = run ? WHEEL_RPM / slow : 0;
  const tpi = tpiOf(Math.max(rpm, 0.001)).toFixed(1);
  const phase = run ? "spinning" : "idle";
  const text = `wheel ${turns.toFixed(0)}° · draft ${DRAFT.toFixed(1)}× · twist ${tpi} tpi · ${phase}`;
  if (readout && readout.textContent !== text) readout.textContent = text;
  stage.setAttribute("aria-valuenow", String(Math.round(turns)));
  stage.setAttribute("aria-valuetext", `Water frame ${phase}, draft ${DRAFT.toFixed(1)}, twist ${tpi} turns per inch`);
};

const hold = () => {
  touring = false;
  clearTimeout(idle);
  idle = setTimeout(() => {
    if (!running && !dragging) {
      touring = !still.matches;
      run();
    }
  }, 4000);
};

const controller = TURN.mount(stage, DATA.turn, {
  follow,
  onHold: () => {
    touring = false;
    clearTimeout(idle);
  },
  onFrame: (turned) => {
    if (!own) {
      angle = target = turned.values.wheel ?? 0;
      show(angle, running);
    }
  },
});

const apply = (deg) => {
  own = true;
  angle = deg;
  target = deg;
  controller.set(follow({ wheel: deg }));
  show(deg, running || Math.abs(target - angle) > 0.01);
  own = false;
};

const wrapDelta = (from, to) => {
  let d = to - from;
  while (d > 180) d -= 360;
  while (d < -180) d += 360;
  return d;
};

const onPointer = (e) => {
  if (!dragging) return;
  const next = controller.angleAt(e.clientX, e.clientY, DATA.wheel[2], "wheel");
  if (next == null) return;
  const delta = wrapDelta(dragAngle, next);
  dragAngle = next;
  apply(dragBase + delta);
  dragBase = angle;
  hold();
};

stage.addEventListener("pointerdown", (e) => {
  if (e.button !== 0) return;
  stage.setPointerCapture(e.pointerId);
  dragging = true;
  running = false;
  dragAngle = controller.angleAt(e.clientX, e.clientY, DATA.wheel[2], "wheel") ?? 0;
  dragBase = angle;
  hold();
});
stage.addEventListener("pointermove", onPointer);
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
    apply(angle + (e.key === "ArrowRight" ? 8 : -8) * slow);
    hold();
  } else if (e.key === " " || e.code === "Space") {
    e.preventDefault();
    running = !running;
    hold();
    run();
  } else if (e.key === "s" || e.key === "S") {
    e.preventDefault();
    slow = slow === 1 ? 5 : slow === 5 ? 20 : 1;
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
    apply(angle);
    frame = 0;
    return;
  }
  if (running) {
    const degPerSec = (WHEEL_RPM / slow) * 6;
    apply(angle + degPerSec * dt);
  } else if (touring) {
    apply(angle + (6 / slow) * dt);
  } else if (Math.abs(wrapDelta(angle, target)) > 0.05) {
    const d = wrapDelta(angle, target);
    apply(angle + d * Math.min(1, 8 * dt));
  } else {
    show(angle, false);
  }
  if (visible && (running || touring || dragging || Math.abs(wrapDelta(angle, target)) > 0.05)) {
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

show(0, false);
apply(0);
run();
