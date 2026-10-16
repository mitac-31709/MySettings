/**
 * Arkwright water frame (1775 Science Museum machine) — truth model.
 *
 * Roller speed ratios 1 : 1.6 : 18.4 (Science Museum Group, inv. 1860-3).
 * Overall draft = front / back = 18.4. Eight flyer spindles on the original;
 * this figure shows four for clarity. Twist (tpi) = flyer rev / yarn delivered.
 * Water wheel → line shaft → roller drums and spindle belt (continuous process).
 */

export const ROLLER_RATIO = Object.freeze([1, 1.6, 18.4]);
export const OVERALL_DRAFT = ROLLER_RATIO[2] / ROLLER_RATIO[0]; // 18.4
export const SPINDLES = 4;
export const HISTORIC_SPINDLES = 8;

/** Wheel revolutions per minute at the figure's "run" speed. */
export const WHEEL_RPM = 12;

/** Flyer : water-wheel ratio through the belt/drum train (chosen so flyers read fast). */
export const FLYER_PER_WHEEL = 48;

/** Delivery roller surface speed relative to wheel (arbitrary units for readout). */
export const DELIVERY_PER_WHEEL = 2.4;

export function flyerRpm(wheelRpm = WHEEL_RPM) {
  return wheelRpm * FLYER_PER_WHEEL;
}

export function deliverySpeed(wheelRpm = WHEEL_RPM) {
  return wheelRpm * DELIVERY_PER_WHEEL;
}

/** Turns of twist per inch of delivered yarn (flyer rev / inches delivered). */
export function twistPerInch(wheelRpm = WHEEL_RPM) {
  const inches = deliverySpeed(wheelRpm) * 60; // per minute, scale units as "inches"
  return inches > 0 ? flyerRpm(wheelRpm) / inches : 0;
}

export function rollerSpeeds(wheelRpm = WHEEL_RPM) {
  const front = deliverySpeed(wheelRpm);
  return ROLLER_RATIO.map((r) => (front * r) / ROLLER_RATIO[2]);
}

export function readout(wheelDeg, running) {
  const turns = ((wheelDeg % 360) + 360) % 360;
  const rpm = running ? WHEEL_RPM : 0;
  const draft = OVERALL_DRAFT.toFixed(1);
  const tpi = twistPerInch(Math.max(rpm, 0.001)).toFixed(1);
  const phase = running ? "spinning" : "idle";
  return {
    text: `wheel ${turns.toFixed(0)}° · draft ${draft}× · twist ${tpi} tpi · ${phase}`,
    aria: `Water frame ${phase}, overall draft ${draft}, twist ${tpi} turns per inch`,
    turns,
    rpm,
    draft: OVERALL_DRAFT,
    tpi: Number(tpi),
    phase,
  };
}
