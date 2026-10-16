/**
 * Crompton spinning mule — truth model.
 *
 * Hybrid of Arkwright's water frame (rollers) and Hargreaves's jenny (moving carriage).
 * Cycle: (1) carriage draws out while spindles twist  (2) backing-off  (3) carriage
 * returns while winding onto the cops. Draw historically ~5 ft (1.52 m). Intermittent,
 * unlike the water frame's continuous flyer twist. Produces finer weft yarn.
 */

export const DRAW_M = 1.52;
export const DRAW_FT = 5;
export const SPINDLES = 6;
export const HISTORIC_SPINDLES_EARLY = 30; // Crompton's first mule ~1779

/** Carriage travel in figure world units (maps to DRAW_M). */
export const TRAVEL = 56;

/** Spindle twist revs during a full outward draw (scaled for readout). */
export const TWIST_ON_DRAW = 48;

export function phaseOf(carriage /* 0…TRAVEL */, returning) {
  const u = carriage / TRAVEL;
  if (returning) {
    if (u > 0.92) return "backing-off";
    return "winding";
  }
  if (u < 0.04) return "ready";
  return "drawing";
}

export function twistTurns(carriage, returning) {
  if (returning) return TWIST_ON_DRAW; // twist already in; winding phase
  return TWIST_ON_DRAW * (carriage / TRAVEL);
}

export function yarnLengthM(carriage) {
  return DRAW_M * (carriage / TRAVEL);
}

export function readout(carriage, returning, running) {
  const phase = phaseOf(carriage, returning);
  const twist = twistTurns(carriage, returning).toFixed(0);
  const metres = yarnLengthM(carriage).toFixed(2);
  const mode = running ? "cycling" : "idle";
  return {
    text: `carriage ${metres} m · ${phase} · twist ${twist} · ${mode}`,
    aria: `Spinning mule ${phase}, carriage at ${metres} metres, ${twist} turns of twist`,
    phase,
    metres: Number(metres),
    twist: Number(twist),
    mode,
  };
}
