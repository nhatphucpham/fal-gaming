'use strict';
const PAL = {
  INK: '#2b2320', CREAM: '#f3e6c8', VERMILION: '#d2462e', GOLD: '#f2c14e',
  STEEL: '#d8dde2', STEEL_DARK: '#8f98a3', LEATHER: '#5b3d2a', WOOD: '#8a5a35',
  SKIN: '#e8b48a', HAIR: '#3a2a22', TUNIC: '#3c5a99', TUNIC_DARK: '#2f4779',
  TROUSERS: '#4a3b33', BOOT: '#2f2622', PAPER: '#e9d6ae',
  IRON: '#a3abb5', STRAW: '#d9b36a', MOSS: '#5d7f45', MOSS_DARK: '#466236', PLUM: '#6a4a9c', PLUM_DARK: '#4f3878',
  BEARD: '#efe7d8', ORB: '#8fe6ff', HORSE: '#a4703f', HORSE_DARK: '#7a5230', MUZZLE: '#d6b089',
};
const D = Math.PI / 180;
const lerp = (a, b, t) => a + (b - a) * t;
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
const hex = (c) => [parseInt(c.slice(1, 3), 16), parseInt(c.slice(3, 5), 16), parseInt(c.slice(5, 7), 16)];
const mix = (c, to, t) => { const a = hex(c), b = hex(to); return '#' + a.map((v, i) => Math.round(lerp(v, b[i], t)).toString(16).padStart(2, '0')).join(''); };
const dark = (c) => mix(c, '#1a1620', 0.14);

// ---- matrices: [a, b, c, d, e, f] as canvas transform; a limb at angle 0 hangs straight down (+y)
const mat = (ang, x, y) => { const c = Math.cos(ang), s = Math.sin(ang); return [c, s, -s, c, x, y]; };
const mm = (m, n) => [m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1], m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3], m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5]];
const ap = (m, x, y) => [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];

// ---- skeleton, seen three-quarters on: the body faces the viewer (enemy) or away (player), turned a little
// to its sword side. F = the sword side (drawn on the right), B = the other side. A flip mirrors the lot.
// Positive angle swings a limb's tip toward the B side.
const UA = 9.5, LA = 9, LEG = 12.5, ANKLE = 2.2, SH = 5.6, HIPW = 2.6;
const BONES = [
  ['root', null, 0, 0], ['torso', 'root', 0, 0], ['head', 'torso', 0, -18.2],
  ['uaB', 'torso', -SH, -14.6], ['laB', 'uaB', 0, UA], ['hB', 'laB', 0, LA],
  ['uaF', 'torso', SH, -14.6], ['laF', 'uaF', 0, UA], ['hF', 'laF', 0, LA],
  ['thB', 'root', -HIPW, 0], ['shB', 'thB', 0, LEG], ['ftB', 'shB', 0, LEG],
  ['thF', 'root', HIPW, 0], ['shF', 'thF', 0, LEG], ['ftF', 'shF', 0, LEG],
];
// joint limits in degrees (the knees are not listed: seen end on they shorten instead of turning); elbows never fold past straight the wrong way round
const LIMIT = { laF: [-150, 20], laB: [-150, 150], head: [-35, 35] };

// ---- a pose: bone angles in degrees plus a few controls
// blade = angle of the weapon on screen (0 toward the sword side, -90 up, 90 down); hip/fF/fB/lF/lB place the hips
// and feet (legs solved by IK); ik = 0 lets the legs use their own angles and the body rest on whatever touches the ground.
// Class controls: wl/wo = weapon length scale (foreshortening) and slide; grip/gw = the B hand holds the weapon at
// `grip` along it (two-handed IK, weight gw); draw/nock = bow string pulled / arrow on the string; ride = sit at `hip`
// on a horse; hph/hg/hl = the horse's gallop phase, gallop amount and rear. kUF/kLF/kUB/kLB = upper/lower arm length
// scale: an arm pointing at or away from the viewer gets shorter on screen, like a bent leg.
const BASE = { root: 0, torso: 0, head: 0, uaF: 0, laF: 0, uaB: 0, laB: 0, thF: 0, shF: 0, thB: 0, shB: 0, ftF: 0, ftB: 0,
  blade: 30, hip: 27, fF: 3.8, fB: -3.8, lF: 0, lB: 0, stF: 0, stB: 0, heF: 0, heB: 0, ik: 1, flat: 1, dx: 0, jump: 0, glow: 0, trail: 0, flash: 0, alpha: 1, eyes: 0,
  wl: 1, wo: 0, grip: 0, gw: 0, draw: 0, nock: 0, tilt: 0, ride: 0, hph: 0, hg: 0, hl: 0, bowUp: 0, kUF: 1, kLF: 1, kUB: 1, kLB: 1 };
// Seen from the front or the back the legs stay under the body: feet close together, one ahead of the other
// (stF/stB, in the direction the unit faces), and a raised heel (heF/heB). Older key poses gave a wide sideways
// stance; P() narrows it and turns a lunge (dx > 0) or a flinch (dx < 0) into a step forward or back.
const P = (o) => {
  const q = Object.assign({}, BASE, o);
  q.fF = 3 + (q.fF - 3.8) * 0.25; q.fB = -3 + (q.fB + 3.8) * 0.25;
  if (o.stF === undefined) {
    if (q.dx > 0) { q.stF = 5; q.stB = -4; q.heB = 0.7; }
    else if (q.dx < 0) { q.stF = -1; q.stB = -4; q.heF = 0.3; }
    else if (q.hip < 26.5 && q.ik === 1) { q.stF = 2; q.stB = -2; }
  }
  return q;
};
const IDLE = P({ uaF: -9, laF: -6, blade: 56, uaB: 12, laB: -12 });
const STANCE = P({ torso: 3, head: -2, uaF: -30, laF: -82, blade: -66, uaB: 20, laB: -40, hip: 26, fF: 5.6, fB: -5.6 });
const back = [0.26, 'io', STANCE];
const gather = [
  [0.32, 'out', P({ head: 3, uaF: -40, laF: -124, blade: -90, uaB: -30, laB: -112, hip: 23.4, fF: 6.6, fB: -6.6, glow: 1 })],
  [0.14, 'lin', P({ head: 4, uaF: -42, laF: -126, blade: -92, uaB: -32, laB: -114, hip: 23.1, fF: 6.6, fB: -6.6, glow: 1 })],
];
const CLIPS = {
  // the enemy cuts down across its body, toward the bottom of the board
  attackDown: [
    [0.17, 'out', P({ torso: 5, head: -2, uaF: -150, laF: -40, blade: -72, uaB: 18, laB: -30, hip: 26.8, fF: 5, fB: -5.5 })],
    [0.09, 'in', P({ torso: -7, head: 4, uaF: 28, laF: 20, blade: -250, uaB: 24, laB: -20, hip: 24, fF: 6.4, fB: -6.4, dx: 4.5, trail: 1 })],
    [0.12, 'lin', P({ torso: -8, head: 4, uaF: 30, laF: 20, blade: -258, uaB: 24, laB: -20, hip: 23.8, fF: 6.4, fB: -6.4, dx: 4.5 })],
    back,
  ],
  // the player cuts upward from the hip to above the far shoulder, toward the top of the board
  attackUp: [
    [0.17, 'out', P({ torso: 6, head: 3, uaF: -16, laF: -30, blade: 64, uaB: 20, laB: -24, hip: 24.4, fF: 6.4, fB: -6.4 })],
    [0.09, 'in', P({ torso: -6, head: -4, uaF: -200, laF: -20, blade: -132, uaB: 26, laB: -26, hip: 26.9, fF: 5, fB: -5, dx: 4.5, trail: 1 })],
    [0.12, 'lin', P({ torso: -7, head: -4, uaF: -204, laF: -18, blade: -140, uaB: 26, laB: -26, hip: 26.9, fF: 5, fB: -5, dx: 4.5 })],
    back,
  ],
  skillDown: gather.concat([
    [0.1, 'in', P({ torso: -9, head: 5, uaF: 32, laF: 20, blade: -252, uaB: 26, laB: -20, hip: 23, fF: 7.2, fB: -7.2, dx: 8, trail: 1, glow: 1 })],
    [0.2, 'lin', P({ torso: -10, head: 5, uaF: 34, laF: 20, blade: -262, uaB: 26, laB: -20, hip: 22.8, fF: 7.2, fB: -7.2, dx: 8, glow: 0.4 })],
    [0.32, 'io', STANCE],
  ]),
  skillUp: gather.concat([
    [0.1, 'in', P({ torso: -7, head: -5, uaF: -204, laF: -14, blade: -130, uaB: 28, laB: -28, hip: 27, fF: 4.4, fB: -4.4, dx: 8, jump: 4, trail: 1, glow: 1 })],
    [0.2, 'lin', P({ torso: -8, head: -5, uaF: -208, laF: -12, blade: -140, uaB: 28, laB: -28, hip: 26.6, fF: 4.6, fB: -4.6, dx: 8, glow: 0.4 })],
    [0.32, 'io', STANCE],
  ]),
  hit: [
    [0.07, 'out', P({ torso: -9, head: -9, uaF: -30, laF: -46, blade: -34, uaB: 22, laB: -14, hip: 25.2, fF: 4, fB: -6.6, dx: -3.5, eyes: 1, flash: 1 })],
    [0.13, 'lin', P({ torso: -8, head: -8, uaF: -28, laF: -44, blade: -32, uaB: 20, laB: -12, hip: 25.2, fF: 4, fB: -6.6, dx: -3.5, eyes: 1 })],
    back,
  ],
  die: (() => {
    const lie = { stF: 0, root: -88, torso: -4, head: -8, uaF: -62, laF: -22, blade: 4, uaB: 40, laB: 30, thF: -12, shF: 22, thB: 6, shB: 14, ftF: -70, ftB: -60, ik: 0, flat: 0, dx: -6, eyes: 1 };
    return [
      [0.26, 'out', P({ torso: 12, head: 14, uaF: -24, laF: -40, blade: 14, uaB: 20, laB: 10, hip: 19, fF: 5.4, fB: -5.4, eyes: 1, flash: 0.6 })],
      [0.34, 'in', P(lie)], [0.5, 'lin', P(lie)], [0.5, 'lin', P(Object.assign({}, lie, { alpha: 0 }))],
      [0.6, 'lin', P(Object.assign({}, IDLE, { alpha: 0 }))], [0.3, 'lin', IDLE],
    ];
  })(),
  cheer: (() => {
    const up = { head: -2, uaF: -166, laF: -8, blade: -88, uaB: 158, laB: 14, eyes: 2 };
    const low = P(Object.assign({}, up, { hip: 23.5 })), high = P(Object.assign({}, up, { jump: 6 })), land = P(Object.assign({}, up, { hip: 25 }));
    return [[0.16, 'out', low], [0.16, 'out', high], [0.15, 'in', land], [0.16, 'out', high], [0.15, 'in', land], [0.35, 'lin', P(up)], [0.3, 'io', IDLE]];
  })(),
};
CLIPS.fall = CLIPS.die.slice(0, 4);
const EASE = { lin: (t) => t, out: (t) => 1 - (1 - t) * (1 - t), in: (t) => t * t, io: (t) => t * t * (3 - 2 * t) };
function walkPose(ph) {
  // a run along the board: the legs swing front to back, not sideways; the trailing foot lifts its heel
  const th = ph * 2 * Math.PI, s = Math.sin(th), c = Math.cos(th);
  const leg = (sn, cs) => ({ st: 5 * sn, l: 4.5 * Math.max(0, cs), he: clamp(Math.max(0, -sn) * 0.9 + Math.max(0, cs) * 0.7, 0, 1) });
  const F = leg(s, c), B = leg(-s, -c);
  return P({ torso: 2 + 3 * s, head: -2 - 2 * s, uaF: -22 + 16 * s, laF: -64, blade: -38 + 12 * s, uaB: 10 - 8 * s, laB: -38 - 12 * s, kLB: 0.85 - 0.15 * s, hip: 24.6 - 0.9 * Math.abs(c), jump: 1.4 * Math.abs(s),
    fF: 3.8, fB: -3.8, stF: F.st, lF: F.l, heF: F.he, stB: B.st, lB: B.l, heB: B.he });
}
function blend(a, b, t) {
  const o = {};
  for (const k in BASE) o[k] = lerp(a[k], b[k], t);
  o.eyes = t > 0.3 ? b.eyes : a.eyes;
  return o;
}

// ---- solve: pose -> world matrix per bone. A leg never bends sideways here: seen from the front or the back a
// bent knee comes toward the viewer or goes away, so the thigh and shin get SHORTER on screen instead (bone scale).
const CONTACT = [['ftF', 2.6, ANKLE, 0], ['ftF', -2.6, ANKLE, 0], ['ftB', 2.6, ANKLE, 0], ['ftB', -2.6, ANKLE, 0],
  ['root', 0, 0, 5.5], ['torso', 0, -14, 7], ['head', 0, -8, 7.4], ['shF', 0, 0, 3], ['shB', 0, 0, 3], ['hF', 0, 1.5, 2.4], ['hB', 0, 1.5, 2.4]];
const LEN = { thF: LEG, shF: LEG, thB: LEG, shB: LEG, uaF: UA, laF: LA, uaB: UA, laB: LA };
function solve(p, view) {
  const dir = view === 'back' ? -1 : 1, a = {}, S = { thF: 1, shF: 1, thB: 1, shB: 1, uaF: p.kUF, laF: p.kLF, uaB: p.kUB, laB: p.kLB };
  for (const [n] of BONES) a[n] = (LIMIT[n] ? clamp(p[n] ?? 0, LIMIT[n][0], LIMIT[n][1]) : (p[n] ?? 0)) * D;
  if (p.ik > 0.001) {
    const rootM = mat(a.root, p.dx, -p.hip);
    for (const s of ['F', 'B']) {
      const hip = ap(rootM, s === 'F' ? HIPW : -HIPW, 0);
      // a foot placed ahead is farther from the viewer for our unit (higher on screen), nearer for the enemy
      const vx = p['f' + s] - hip[0], vy = -ANKLE - p['l' + s] + dir * p['st' + s] * 0.5 - hip[1];
      const d = Math.min(Math.hypot(vx, vy), 2 * LEG), short = 2 * LEG - d, share = dir < 0 ? 0.7 : 0.35;
      const sS = clamp(1 - short * share / LEG, 0.3, 1), sT = clamp(d / LEG - sS, 0.3, 1);
      a['th' + s] = lerp(a['th' + s], Math.atan2(-vx, vy) - a.root, p.ik); a['sh' + s] = lerp(a['sh' + s], 0, p.ik);
      S['th' + s] = lerp(1, sT, p.ik); S['sh' + s] = lerp(1, sS, p.ik);
    }
  }
  const run = (y) => {
    const M = {}, W = {};
    for (const [n, par, ox, oy0] of BONES) {
      let ang = a[n], oy = oy0;
      if (S[par]) oy = LEN[par] * S[par];
      if (n === 'ftF' || n === 'ftB') ang = lerp(ang, -W[par], p.flat);
      if (n === 'hF') ang = p.blade * D - W[par];
      if (n === 'hB') ang = 0;
      if (!par) { M[n] = mat(ang, p.dx, y); W[n] = ang; } else { M[n] = mm(M[par], mat(ang, ox, oy)); W[n] = W[par] + ang; }
    }
    return M;
  };
  let M = run(0), low = -1e9;
  if (p.gw > 0.001) { reachB(M, a, p); M = run(0); }
  for (const [n, x, y, r] of CONTACT) low = Math.max(low, ap(M[n], x, y)[1] + r);
  M = run(lerp(lerp(-low, -p.hip, p.ik), -p.hip, p.ride) - p.jump);
  M.S = S; M.heel = { ftF: p.heF * p.ik, ftB: p.heB * p.ik }; M.world = [1, 0, 0, 1, 0, 0];
  return M;
}
// two-handed weapons: the B arm reaches for a point `grip` along the weapon (two-bone IK, elbow kept low)
function reachB(M, a, p) {
  const L1 = UA * p.kUB, L2 = LA * p.kLB + 1.5, S0 = ap(M.uaB, 0, 0), T = ap(M.hF, p.grip * p.wl + p.wo, 1.5), vx = T[0] - S0[0], vy = T[1] - S0[1];
  const d = clamp(Math.hypot(vx, vy), 1, L1 + L2 - 0.01), base = Math.atan2(-vx, vy);
  const al = Math.acos(clamp((L1 * L1 + d * d - L2 * L2) / (2 * L1 * d), -1, 1));
  let best = null;
  for (const sg of [1, -1]) {
    const wU = base + sg * al, E = [S0[0] - Math.sin(wU) * L1, S0[1] + Math.cos(wU) * L1], wL = Math.atan2(-(T[0] - E[0]), T[1] - E[1]);
    if (!best || E[1] > best.y) best = { wU, wL, y: E[1] };
  }
  const near = (x, ref) => x + 2 * Math.PI * Math.round((ref - x) / (2 * Math.PI)), wT = a.root + a.torso;
  a.uaB = lerp(a.uaB, near(best.wU - wT, a.uaB), p.gw); a.laB = lerp(a.laB, near(best.wL - best.wU, a.laB), p.gw);
}

// author an arm by points in torso space (shoulder -> elbow E -> fist centre H). A bone shorter on screen than its
// length is foreshortened (k scale). With `blade` the F fist holds a weapon at that screen angle; without, the fist
// continues the forearm (and for the F arm the returned blade keeps it so).
function armTo(s, E, H, blade) {
  const S0 = [s === 'F' ? SH : -SH, -14.6], v1 = [E[0] - S0[0], E[1] - S0[1]], wU = Math.atan2(-v1[0], v1[1]);
  const b = blade === undefined ? null : blade * D, W = b === null ? H : [H[0] + 1.5 * Math.sin(b), H[1] - 1.5 * Math.cos(b)];
  const v2 = [W[0] - E[0], W[1] - E[1]], wL = Math.atan2(-v2[0], v2[1]), l2 = Math.hypot(...v2) - (b === null ? 1.5 : 0);
  const o = { ['ua' + s]: wU / D, ['la' + s]: ((wL - wU) / D + 540) % 360 - 180, ['kU' + s]: clamp(Math.hypot(...v1) / UA, 0.2, 1.1), ['kL' + s]: clamp(l2 / LA, 0.2, 1.1) };
  if (s === 'F' && b === null) o.blade = wL / D;
  return o;
}

// ---- pieces. Each is drawn in its bone's own space with the joint at (0, 0). `z` is the draw order per view
// (null = not drawn in that view): seen from the front the arms and weapon lie over the body; seen from behind the
// body covers them. A piece with `draw` paints itself (outline included) instead of one filled path.
const capsule = (c, r0, r1, len) => { c.arc(0, 0, r0, Math.PI, 0); c.lineTo(r1, len); c.arc(0, len, r1, 0, Math.PI); c.closePath(); };
const arm = (c, k) => capsule(c, 2.8, 2.4, UA * k.s), fore = (c, k) => capsule(c, 2.4, 2, LA * k.s), fist = (c) => c.arc(0, 1.5, 2.3, 0, 7);
const thigh = (c, k) => capsule(c, 3.3, 2.8, LEG * k.s), shin = (c, k) => capsule(c, 2.8, 2.2, LEG * k.s);
const cuff = (c, t) => { c.fillStyle = t(PAL.LEATHER); c.fillRect(-3, -0.2, 6, 2.2); };
// a closed shape with the same dark outline as the pieces (stroke first, fill over it)
const shp = (c, t, col, fn, lw = 2.2) => { c.beginPath(); fn(); c.lineJoin = 'round'; c.strokeStyle = t(PAL.INK); c.lineWidth = lw; c.stroke(); c.fillStyle = t(col); c.fill(); };
const wlo = (k) => (k && k.p ? [k.p.wl, k.p.wo] : [1, 0]);
const PIECES = [
  { id: 'uaB', bone: 'uaB', z: { front: 4, back: 0 }, col: dark(PAL.TUNIC), path: arm },
  { id: 'laB', bone: 'laB', z: { front: 4, back: 0 }, col: dark(PAL.SKIN), path: fore, detail: bracer },
  { id: 'hB', bone: 'hB', z: { front: 4, back: 0 }, col: dark(PAL.SKIN), path: fist },
  { id: 'thB', bone: 'thB', z: { front: 0, back: 1 }, col: dark(PAL.TROUSERS), path: thigh },
  { id: 'shB', bone: 'shB', z: { front: 0, back: 1 }, col: dark(PAL.BOOT), path: shin, detail: cuff },
  { id: 'ftB', bone: 'ftB', z: { front: 0, back: 1 }, col: dark(PAL.BOOT), path: footPath, detail: footDetail },
  { id: 'thF', name: 'Đùi', bone: 'thF', z: { front: 1, back: 2 }, col: PAL.TROUSERS, path: thigh },
  { id: 'shF', name: 'Ống chân', bone: 'shF', z: { front: 1, back: 2 }, col: PAL.BOOT, path: shin, detail: cuff },
  { id: 'ftF', name: 'Bàn chân', bone: 'ftF', z: { front: 1, back: 2 }, col: PAL.BOOT, path: footPath, detail: footDetail },
  { id: 'skirt', name: 'Váy giáp', bone: 'root', z: { front: 2, back: 5 }, col: PAL.TUNIC_DARK, path: (c) => { c.moveTo(-6.4, -1); c.lineTo(6.4, -1); c.lineTo(7.8, 5); c.lineTo(-7.8, 5); c.closePath(); },
    detail: (c, t) => { c.strokeStyle = t(PAL.GOLD); c.lineWidth = 0.9; c.beginPath(); c.moveTo(-7.4, 3.9); c.lineTo(7.4, 3.9); c.stroke(); c.strokeStyle = t(PAL.INK); c.lineWidth = 0.6; c.beginPath(); c.moveTo(0, 0.5); c.lineTo(0, 4.8); c.stroke(); } },
  { id: 'torso', bone: 'torso', z: { front: 2, back: 5 }, col: PAL.TUNIC, path: torsoPath, detail: torsoKit({ armor: 'plate', strap: true, scarf: true }) },
  { id: 'head', bone: 'head', z: { front: 3, back: 6 }, col: PAL.SKIN, path: headPath, detail: helmHead({ plume: true }) },
  { id: 'sword', name: 'Kiếm', bone: 'hF', z: { front: 5, back: 3 }, col: PAL.STEEL, path: (c) => { c.moveTo(3.6, 0.1); c.lineTo(23.5, 0.2); c.lineTo(27, 1.5); c.lineTo(23.5, 2.9); c.lineTo(3.6, 3); c.closePath(); c.rect(2.6, -1.6, 1.8, 6.2); c.rect(-3.4, 0.6, 6, 1.9); c.arc(-4, 1.5, 1.5, 0, 7); }, detail: swordDetail },
  { id: 'uaF', name: 'Bắp tay', bone: 'uaF', z: { front: 6, back: 4 }, col: PAL.TUNIC, path: arm },
  { id: 'laF', name: 'Cẳng tay', bone: 'laF', z: { front: 6, back: 4 }, col: PAL.SKIN, path: fore, detail: bracer },
  { id: 'hF', name: 'Bàn tay', bone: 'hF', z: { front: 6, back: 4 }, col: PAL.SKIN, path: fist },
  { id: 'pauldronB', bone: 'uaB', z: { front: 7, back: 7 }, col: PAL.STEEL, path: pauldronPath, detail: pauldronDetail },
  { id: 'pauldron', name: 'Giáp vai', bone: 'uaF', z: { front: 7, back: 7 }, col: PAL.STEEL, path: pauldronPath, detail: pauldronDetail },
];
function torsoPath(c) { c.moveTo(-6, 1.2); c.lineTo(6, 1.2); c.lineTo(7.2, -11.6); c.quadraticCurveTo(7.3, -17.4, 2.4, -18.1); c.lineTo(-2.4, -18.1); c.quadraticCurveTo(-7.3, -17.4, -7.2, -11.6); c.closePath(); }
function headPath(c) { c.arc(0, -8, 7, 0, 7); c.rect(-2, -2.4, 4, 3.4); }
function pauldronPath(c) { c.arc(0, 0.2, 4.1, Math.PI * 0.95, Math.PI * 2.05); c.quadraticCurveTo(0, 4.6, -4.1, 0.9); c.closePath(); }
function pauldronDetail(c, t) { c.strokeStyle = t(PAL.STEEL_DARK); c.lineWidth = 0.7; c.beginPath(); c.arc(0, 0.6, 2.6, Math.PI * 1.1, Math.PI * 1.9); c.stroke(); c.fillStyle = t(PAL.GOLD); c.beginPath(); c.arc(0, 1.6, 0.8, 0, 7); c.fill(); }
// A foot seen end on: from behind a heel block, and the sole showing below it when the heel lifts;
// from the front a toe cap, which tucks up when the heel lifts.
function footPath(c, k) {
  const h = k.heel || 0, bottom = k.view === 'back' ? ANKLE + 6.5 * h : ANKLE + 1.2 - 1.6 * h, w = 2.7 + (k.view === 'back' ? 0.5 * h : 0.3);
  c.moveTo(-2.4, -2.2); c.lineTo(2.4, -2.2); c.quadraticCurveTo(w + 0.4, bottom - 2, w - 0.6, bottom); c.quadraticCurveTo(0, bottom + 1.1, -w + 0.6, bottom); c.quadraticCurveTo(-w - 0.4, bottom - 2, -2.4, -2.2); c.closePath();
}
function footDetail(c, t, p, view, k) {
  const h = k.heel || 0;
  if (view === 'back' && h > 0.12) { const b = ANKLE + 6.5 * h; c.fillStyle = t('#cdb9a0'); c.beginPath(); c.moveTo(-2.1, 0.6); c.lineTo(2.1, 0.6); c.quadraticCurveTo(2.8, b - 2, 1.7, b - 0.5); c.quadraticCurveTo(0, b + 0.3, -1.7, b - 0.5); c.quadraticCurveTo(-2.8, b - 2, -2.1, 0.6); c.closePath(); c.fill(); }
  else if (view !== 'back') { c.strokeStyle = t(PAL.LEATHER); c.lineWidth = 0.7; c.beginPath(); c.moveTo(-2.3, 0.9); c.quadraticCurveTo(0, -0.4, 2.3, 0.9); c.stroke(); }
}
function bracer(c, t, p, view, k) { const s = k ? k.s : 1; c.fillStyle = t(PAL.LEATHER); c.beginPath(); c.moveTo(-2.4, 2.6 * s); c.lineTo(2.4, 2.6 * s); c.lineTo(2.1, 7.6 * s); c.lineTo(-2.1, 7.6 * s); c.closePath(); c.fill(); c.strokeStyle = t(PAL.GOLD); c.lineWidth = 0.6; c.beginPath(); c.moveTo(-2.3, 3.2 * s); c.lineTo(2.3, 3.2 * s); c.stroke(); }
function plate(c) { c.beginPath(); c.moveTo(-6.4, -6.2); c.quadraticCurveTo(0, -4.2, 6.4, -6.2); c.lineTo(7.2, -11.6); c.quadraticCurveTo(7.2, -16.5, 3.2, -17.1); c.lineTo(-3.2, -17.1); c.quadraticCurveTo(-7.2, -16.5, -7.2, -11.6); c.closePath(); }
// torso dressings: armor = plate (Kiếm, Kỵ), lamellar (Khiên), quilt (Thương), vest (Cung), robe (Pháp)
function torsoKit(o) {
  return (c, t, p, view) => {
    const sway = Math.sin(performance.now() / 420) * 0.8;
    c.strokeStyle = t(PAL.INK); c.lineWidth = 0.7;
    if (o.armor === 'plate') { c.fillStyle = t(PAL.STEEL); plate(c); c.fill(); c.stroke(); }
    else if (o.armor === 'lamellar') {
      c.fillStyle = t(PAL.IRON); plate(c); c.fill(); c.save(); c.clip();
      c.strokeStyle = t(PAL.STEEL_DARK); c.lineWidth = 0.55;
      for (let y = -15.6, r = 0; y < -5; y += 2.1, r++) { c.beginPath(); c.moveTo(-8, y); c.lineTo(8, y); for (let x = -7 + (r % 2) * 1.1; x < 8; x += 2.2) { c.moveTo(x, y); c.lineTo(x, y + 2.1); } c.stroke(); }
      c.restore(); c.strokeStyle = t(PAL.INK); c.lineWidth = 0.7; plate(c); c.stroke();
    } else if (o.armor === 'quilt') {
      c.fillStyle = t(PAL.CREAM); plate(c); c.fill(); c.save(); c.clip();
      c.strokeStyle = t('#c9b48c'); c.lineWidth = 0.6; c.beginPath(); for (let x = -6; x <= 6; x += 3) { c.moveTo(x, -18); c.lineTo(x, -4); } c.stroke();
      c.restore(); c.strokeStyle = t(PAL.INK); c.lineWidth = 0.7; plate(c); c.stroke();
      c.strokeStyle = t(PAL.VERMILION); c.lineWidth = 1.1; c.beginPath(); c.moveTo(-6.6, -6.6); c.quadraticCurveTo(0, -4.6, 6.6, -6.6); c.stroke();
    } else if (o.armor === 'vest') { c.fillStyle = t('#7a5034'); plate(c); c.fill(); c.stroke(); }
    if (o.armor === 'robe') {
      // robe: gold-edged collar in front, a gold seam behind, a red sash
      c.strokeStyle = t(PAL.GOLD); c.lineWidth = 1.2; c.beginPath();
      if (view === 'back') { c.moveTo(-5, -17.4); c.quadraticCurveTo(0, -15.8, 5, -17.4); c.moveTo(0, -16.4); c.lineTo(0, -2); }
      else { c.moveTo(-3.6, -17.6); c.lineTo(1.2, -9.6); c.lineTo(5, -17.6); c.moveTo(1.2, -9.6); c.lineTo(1.2, -2); }
      c.stroke(); c.fillStyle = t(PAL.VERMILION); c.fillRect(-6.1, -2.4, 12.2, 3); c.strokeStyle = t(PAL.INK); c.lineWidth = 0.6; c.strokeRect(-6.1, -2.4, 12.2, 3);
      if (view !== 'back') { c.beginPath(); c.moveTo(2.4, 0.4); c.lineTo(1.4, 4.6); c.lineTo(3.4, 4.2); c.closePath(); c.fill(); c.stroke(); }
      return;
    }
    c.fillStyle = t(PAL.LEATHER); c.fillRect(-6.1, -1.6, 12.2, 2.6);
    if (view === 'back') {
      // back plate with a spine line, the scabbard strap across it, and the red scarf's knot and two tails
      if (o.armor === 'plate') { c.strokeStyle = t(PAL.STEEL_DARK); c.beginPath(); c.moveTo(0, -16.6); c.lineTo(0, -5.2); c.moveTo(-5.4, -10.5); c.quadraticCurveTo(0, -8.6, 5.4, -10.5); c.stroke(); }
      if (o.strap) {
        c.strokeStyle = t(PAL.INK); c.lineWidth = 3.4; c.lineCap = 'round'; c.beginPath(); c.moveTo(-6.6, -15); c.lineTo(7.4, 2.6); c.stroke();
        c.strokeStyle = t(PAL.WOOD); c.lineWidth = 2.2; c.beginPath(); c.moveTo(-6.6, -15); c.lineTo(7.4, 2.6); c.stroke();
        c.fillStyle = t(PAL.GOLD); c.beginPath(); c.arc(7.4, 2.6, 1.3, 0, 7); c.fill(); c.lineCap = 'butt';
      }
      if (o.scarf) {
        c.fillStyle = t(PAL.VERMILION); c.strokeStyle = t(PAL.INK); c.lineWidth = 0.7; c.lineCap = 'butt';
        for (const [x, w, len, k] of [[-1.6, 2.6, 12, 1], [1.4, 2.4, 9.5, -0.7]]) { c.beginPath(); c.moveTo(x - w / 2, -16.6); c.quadraticCurveTo(x - w / 2 + sway * k, -16.6 + len / 2, x - w / 2 + sway * 1.8 * k - 0.6, -16.6 + len); c.lineTo(x + w / 2 + sway * 1.8 * k + 0.4, -16.6 + len - 1.2); c.quadraticCurveTo(x + w / 2 + sway * k, -16.6 + len / 2, x + w / 2, -16.6); c.closePath(); c.fill(); c.stroke(); }
        c.beginPath(); c.ellipse(0, -17.2, 4.6, 2, 0, 0, 7); c.fill(); c.stroke();
      }
    } else {
      if (o.armor === 'plate') { c.strokeStyle = t(PAL.STEEL_DARK); c.beginPath(); c.moveTo(1, -16.6); c.lineTo(1.1, -5.2); c.stroke(); c.fillStyle = t('#ffffff'); c.globalAlpha *= 0.55; c.beginPath(); c.ellipse(4.2, -12.4, 1, 3, 0.1, 0, 7); c.fill(); c.globalAlpha /= 0.55; }
      if (o.belt2) { c.strokeStyle = t(PAL.LEATHER); c.lineWidth = 1.8; c.beginPath(); c.moveTo(6.4, -16.4); c.lineTo(-6, -3); c.stroke(); }
      c.fillStyle = t(PAL.GOLD); c.fillRect(-0.2, -1.5, 2.4, 2.4);
      if (o.scarf) { c.fillStyle = t(PAL.VERMILION); c.strokeStyle = t(PAL.INK); c.lineWidth = 0.7; c.beginPath(); c.ellipse(0.2, -17.3, 4.8, 2, 0, 0, 7); c.fill(); c.stroke(); }
    }
  };
}

// ---- heads. Head space: skull centre (0, -8), radius 7; the face is turned a little toward the F side.
function face(c, t, eyes, mouth = true) {
  c.strokeStyle = t(PAL.INK); c.fillStyle = t(PAL.INK); c.lineCap = 'round'; c.lineWidth = 0.8;
  for (const [x, s] of [[-0.6, 0.95], [4.8, 0.95]]) {
    c.beginPath();
    if (eyes < 0.5) { c.ellipse(x, -5.3, 0.85 * s, 1.25 * s, 0, 0, 7); c.fill(); }
    else if (eyes < 1.5) { c.moveTo(x - 1.1 * s, -5.6); c.lineTo(x + 1 * s, -5); c.stroke(); }
    else { c.arc(x, -4.9, 1.1 * s, Math.PI * 1.1, Math.PI * 1.9); c.stroke(); }
  }
  if (!mouth) return;
  c.lineWidth = 0.6; c.beginPath();
  if (eyes > 1.5) c.arc(2.2, -3, 1.4, 0.1, Math.PI * 0.9); else { c.moveTo(1.3, -2.5); c.lineTo(3.2, -2.5); }
  c.stroke();
}
const hairFront = (c, t, col = PAL.HAIR) => { c.fillStyle = t(col); c.beginPath(); c.arc(0, -8, 7, Math.PI * 0.7, Math.PI * 1.05); c.lineTo(-4.4, -8); c.closePath(); c.fill(); };
const hairBack = (c, t, col = PAL.HAIR) => { c.fillStyle = t(col); c.beginPath(); c.arc(0, -8, 7, 0.15 * Math.PI, 0.85 * Math.PI); c.closePath(); c.fill(); };
// a pheasant tail feather (Kỵ): gold with dark bars
function feather(c, t, pts) {
  c.lineCap = 'round'; c.beginPath(); c.moveTo(pts[0], pts[1]); c.bezierCurveTo(pts[2], pts[3], pts[4], pts[5], pts[6], pts[7]);
  c.strokeStyle = t(PAL.INK); c.lineWidth = 2.8; c.stroke(); c.strokeStyle = t(PAL.GOLD); c.lineWidth = 1.5; c.stroke();
  c.setLineDash([1.1, 1.7]); c.strokeStyle = t(PAL.LEATHER); c.lineWidth = 1.5; c.stroke(); c.setLineDash([]);
}
// helmet: Kiếm (plume), Kỵ (two pheasant feathers), Khiên (iron, cheek guards, no plume)
function helmHead(o) {
  const dome = o.iron ? PAL.IRON : PAL.STEEL;
  return (c, t, p, view) => {
    const eyes = p ? p.eyes : 0, sway = Math.sin(performance.now() / 380) * 0.8;
    c.strokeStyle = t(PAL.INK); c.lineWidth = 0.7;
    if (o.feathers) { feather(c, t, [-1.2, -15, -2.4, -21 + sway, -6.5, -24.5, -10.5, -22 + sway]); feather(c, t, [1.4, -15, 3, -21 - sway, 7, -25, 11, -22.5 - sway]); c.lineWidth = 0.7; }
    if (view === 'back') {
      // the helmet from behind: the full dome, a neck guard, and the plume falling toward the viewer
      hairBack(c, t);
      c.fillStyle = t(PAL.STEEL_DARK); c.beginPath(); c.moveTo(-7, -7); c.lineTo(7, -7); c.lineTo(7.8, -3.2); c.quadraticCurveTo(0, -1.2, -7.8, -3.2); c.closePath(); c.fill(); c.stroke();
      if (o.cheeks) { c.fillStyle = t(dome); for (const s of [-1, 1]) { c.beginPath(); c.moveTo(s * 6.8, -7.4); c.lineTo(s * 8.6, -7.4); c.lineTo(s * 8.2, -2.6); c.lineTo(s * 6.6, -2.2); c.closePath(); c.fill(); c.stroke(); } }
      c.fillStyle = t(dome); c.beginPath(); c.arc(0, -8.6, 7.5, Math.PI * 0.98, Math.PI * 2.02); c.lineTo(7.5, -6.4); c.lineTo(-7.5, -6.4); c.closePath(); c.fill(); c.stroke();
      c.fillStyle = t(o.iron ? PAL.STEEL_DARK : PAL.GOLD); c.fillRect(-7.2, -8.2, 14.4, 1.3);
      c.fillStyle = t('#ffffff'); c.globalAlpha *= 0.5; c.beginPath(); c.ellipse(3.2, -12.6, 2.2, 1.1, -0.5, 0, 7); c.fill(); c.globalAlpha /= 0.5;
      if (o.plume) { c.fillStyle = t(PAL.VERMILION); c.beginPath(); c.moveTo(-1.4, -16.4); c.quadraticCurveTo(-4.6, -20.5, -0.4, -21); c.quadraticCurveTo(3.6, -20, 2.2, -14.6); c.quadraticCurveTo(1.6, -11.4, 0.4, -9.6); c.quadraticCurveTo(-1.8, -12, -1.4, -16.4); c.closePath(); c.fill(); c.stroke(); }
      if (o.iron) { c.fillStyle = t(PAL.GOLD); c.beginPath(); c.moveTo(-1.2, -15.8); c.lineTo(0, -19.4); c.lineTo(1.2, -15.8); c.closePath(); c.fill(); c.stroke(); }
      return;
    }
    hairFront(c, t);
    if (o.plume) { c.fillStyle = t(PAL.VERMILION); c.beginPath(); c.moveTo(-0.8, -15.8); c.quadraticCurveTo(-5.6, -21.6, -9.4, -16.4); c.quadraticCurveTo(-5.8, -17.6, -2.4, -14.6); c.closePath(); c.fill(); c.stroke(); }
    if (o.iron) { c.fillStyle = t(PAL.GOLD); c.beginPath(); c.moveTo(-1.2, -15.8); c.lineTo(0, -19.4); c.lineTo(1.2, -15.8); c.closePath(); c.fill(); c.stroke(); }
    c.fillStyle = t(dome);
    c.beginPath(); c.arc(0, -8.6, 7.5, Math.PI * 1.02, Math.PI * 1.98); c.lineTo(8.4, -9.2); c.lineTo(8.2, -7.7); c.lineTo(-7.6, -7.7); c.closePath(); c.fill(); c.stroke();
    c.fillStyle = t(o.iron ? PAL.STEEL_DARK : PAL.GOLD); c.fillRect(-7.4, -9.6, 15.4, 1.3);
    if (o.cheeks) {
      // cheek guards hang from the rim over both cheeks; the far one is narrow
      c.fillStyle = t(dome);
      c.beginPath(); c.moveTo(-7.7, -7.9); c.lineTo(-3.4, -7.9); c.lineTo(-3.2, -3.6); c.quadraticCurveTo(-5, -1.2, -7.2, -2.2); c.closePath(); c.fill(); c.stroke();
      c.beginPath(); c.moveTo(6.6, -7.9); c.lineTo(8.3, -7.9); c.lineTo(8, -2.8); c.lineTo(6.6, -2.4); c.closePath(); c.fill(); c.stroke();
      c.fillStyle = t(PAL.GOLD); c.beginPath(); c.arc(-5.4, -5.6, 0.6, 0, 7); c.fill();
    } else { c.fillStyle = t(PAL.STEEL); c.beginPath(); c.moveTo(1.4, -8.4); c.lineTo(3, -8.4); c.lineTo(2.6, -4.6); c.lineTo(1.8, -4.6); c.closePath(); c.fill(); c.stroke(); }
    c.fillStyle = t('#ffffff'); c.globalAlpha *= 0.5; c.beginPath(); c.ellipse(3, -13, 2.2, 1.1, -0.5, 0, 7); c.fill(); c.globalAlpha /= 0.5;
    face(c, t, eyes, !o.cheeks || true);
  };
}
// nón trận (Thương): a conical war hat with a gold knob and a red chin strap
function nonTran(c, t, p, view) {
  const eyes = p ? p.eyes : 0, cone = () => { c.moveTo(-12.6, -9.6); c.lineTo(0, -23); c.lineTo(12.6, -9.6); c.ellipse(0, -9.6, 12.6, 2.6, 0, 0, Math.PI); c.closePath(); };
  if (view === 'back') {
    hairBack(c, t); c.fillStyle = t(PAL.HAIR); c.beginPath(); c.arc(0, -8, 7, Math.PI, 0); c.fill();
    c.strokeStyle = t('#5a4438'); c.lineWidth = 0.7; c.beginPath(); c.moveTo(-4.6, -7); c.quadraticCurveTo(-3.6, -3.4, -1.6, -2); c.moveTo(4.6, -7); c.quadraticCurveTo(3.6, -3.4, 1.6, -2); c.stroke();
    shp(c, t, PAL.HAIR, () => c.arc(0, -4.6, 2.4, 0, 7), 1.2); c.fillStyle = t(PAL.VERMILION); c.fillRect(-2.2, -6.2, 4.4, 1);
  } else {
    hairFront(c, t); face(c, t, eyes);
    c.strokeStyle = t(PAL.VERMILION); c.lineWidth = 0.9; c.beginPath(); c.moveTo(-6.4, -9); c.quadraticCurveTo(-5.4, -0.6, 1.8, -0.8); c.quadraticCurveTo(6.6, -1, 7.2, -9); c.stroke();
  }
  shp(c, t, PAL.STRAW, cone, 1.8);
  c.strokeStyle = t('#b48d4c'); c.lineWidth = 0.55; c.beginPath(); for (const x of [-8, -4, 0, 4, 8]) { c.moveTo(0, -22.4); c.lineTo(x, -7.6 + Math.abs(x) * -0.1); } c.stroke();
  c.strokeStyle = t(PAL.VERMILION); c.lineWidth = 1.3; c.beginPath(); c.ellipse(0, -9.6, 12.2, 2.3, 0, 0, Math.PI); c.stroke();
  shp(c, t, PAL.GOLD, () => c.arc(0, -23, 1.5, 0, 7), 1.4);
}
// hood (Cung): green hood with a point at the back
function hood(c, t, p, view) {
  const eyes = p ? p.eyes : 0, out = () => { c.moveTo(-8.6, -0.6); c.quadraticCurveTo(-10.4, -12, -5, -16.4); c.quadraticCurveTo(-7.6, -19.6, -10.6, -19.4); c.quadraticCurveTo(-5, -21.4, 0.6, -16.6); c.quadraticCurveTo(9.6, -15, 9, -0.6); c.quadraticCurveTo(0, 1.4, -8.6, -0.6); c.closePath(); };
  shp(c, t, PAL.MOSS, out, 1.8);
  if (view === 'back') {
    c.strokeStyle = t(PAL.MOSS_DARK); c.lineWidth = 0.9; c.beginPath(); c.moveTo(0.4, -16.4); c.quadraticCurveTo(-0.6, -8, 0.2, 0); c.stroke();
    shp(c, t, PAL.MOSS_DARK, () => { c.moveTo(-1.6, -1.2); c.lineTo(1.8, -1.2); c.lineTo(0.4, 4.6); c.closePath(); }, 1.4);
    return;
  }
  shp(c, t, PAL.SKIN, () => c.ellipse(2.1, -6.4, 5.4, 5.6, 0, 0, 7), 1.2);
  c.fillStyle = t(PAL.HAIR); c.beginPath(); c.ellipse(1.4, -10.6, 4.6, 1.7, 0, Math.PI, 0); c.fill();
  face(c, t, eyes);
}
// pointed drooping hat and white beard (Pháp)
function mageHat(c, t, p, view) {
  const eyes = p ? p.eyes : 0, sway = Math.sin(performance.now() / 500) * 0.6;
  if (view === 'back') { c.fillStyle = t('#cfc6b6'); c.beginPath(); c.arc(0, -8, 7, 0, 7); c.fill(); c.strokeStyle = t('#a99f8e'); c.lineWidth = 0.6; c.beginPath(); for (const x of [-3.4, 0, 3.4]) { c.moveTo(x, -9); c.quadraticCurveTo(x * 1.1, -4, x * 0.9, -1.4); } c.stroke(); }
  else {
    hairFront(c, t, PAL.BEARD); face(c, t, eyes, false);
    shp(c, t, PAL.BEARD, () => { c.moveTo(-2.6, -3.6); c.quadraticCurveTo(-2.4, 1.6, 2.6, 4.2); c.quadraticCurveTo(7.6, 1.2, 7, -3.6); c.quadraticCurveTo(4.6, -2.2, 2.2, -3); c.quadraticCurveTo(0, -2.2, -2.6, -3.6); c.closePath(); }, 1.2);
  }
  shp(c, t, PAL.PLUM_DARK, () => c.ellipse(0.4, -10.2, 12.6, 2.8, 0, 0, 7), 1.8);
  shp(c, t, PAL.PLUM, () => { c.moveTo(-6.6, -10.6); c.quadraticCurveTo(-4, -21, 0.6, -25.6); c.quadraticCurveTo(7, -28.6, 11 + sway, -22); c.quadraticCurveTo(6.6, -24, 4.2, -21.4); c.quadraticCurveTo(5.6, -15, 7.2, -10.6); c.quadraticCurveTo(0, -9.2, -6.6, -10.6); c.closePath(); }, 1.8);
  c.fillStyle = t(PAL.GOLD); c.beginPath(); c.moveTo(-6.3, -12.4); c.quadraticCurveTo(0.4, -11, 6.9, -12.4); c.lineTo(7.2, -10.6); c.quadraticCurveTo(0.4, -9.2, -6.6, -10.6); c.closePath(); c.fill();
  if (view !== 'back') { c.beginPath(); for (let i = 0; i < 10; i++) { const r = i % 2 ? 0.8 : 2, a = i * Math.PI / 5 - Math.PI / 2; c.lineTo(0.9 + r * Math.cos(a), -16.4 + r * Math.sin(a)); } c.closePath(); c.fill(); }
}
function swordDetail(c, t) {
  c.fillStyle = t(PAL.GOLD); c.fillRect(2.6, -1.6, 1.8, 6.2); c.beginPath(); c.arc(-4, 1.5, 1.5, 0, 7); c.fill();
  c.fillStyle = t(PAL.LEATHER); c.fillRect(-3.4, 0.6, 6, 1.9);
  c.strokeStyle = t(PAL.STEEL_DARK); c.lineWidth = 0.5; c.beginPath(); c.moveTo(4.6, 1.5); c.lineTo(25.4, 1.5); c.stroke();
  c.strokeStyle = t(PAL.INK); c.lineWidth = 0.5; c.strokeRect(2.6, -1.6, 1.8, 6.2);
}

// ---- weapons and gear of the other classes (hand space: x runs along the weapon, its centre line at y = 1.5).
// wl < 1 foreshortens a pole that points at or away from the viewer; its head then grows a little (nearer).
const headSc = (l) => 1 + (1 - l) * 0.9, headLen = (l) => clamp(l * 1.25, 0.55, 1);
function spearPath(c, k) {
  const [l, o] = wlo(k), X = (x) => x * l + o, s = headSc(l), h = headLen(l), b = X(33);
  c.rect(X(-17), 0.65, b - X(-17), 1.7);
  c.moveTo(b, 1.5 - 1.1 * s); c.quadraticCurveTo(b + 4 * h, 1.5 - 2.9 * s, b + 12 * h, 1.5); c.quadraticCurveTo(b + 4 * h, 1.5 + 2.9 * s, b, 1.5 + 1.1 * s); c.closePath();
}
function spearDetail(c, t, p, view, k) {
  const [l, o] = wlo(k), s = headSc(l), h = headLen(l), b = 33 * l + o, sw = Math.sin(performance.now() / 300) * 0.7;
  c.fillStyle = t(PAL.STEEL); c.beginPath(); c.moveTo(b, 1.5 - 1.1 * s); c.quadraticCurveTo(b + 4 * h, 1.5 - 2.9 * s, b + 12 * h, 1.5); c.quadraticCurveTo(b + 4 * h, 1.5 + 2.9 * s, b, 1.5 + 1.1 * s); c.closePath(); c.fill();
  c.strokeStyle = t(PAL.STEEL_DARK); c.lineWidth = 0.5; c.beginPath(); c.moveTo(b + 1, 1.5); c.lineTo(b + 10 * h, 1.5); c.stroke();
  shp(c, t, PAL.VERMILION, () => { c.moveTo(b, -0.2); c.quadraticCurveTo(b - 3, -2.6, b - 6.6, -1.8 + sw); c.lineTo(b - 5, 1.5); c.lineTo(b - 6.6, 4.8 + sw); c.quadraticCurveTo(b - 3, 5.6, b, 3.2); c.closePath(); }, 1.4);
  c.fillStyle = t(PAL.GOLD); c.fillRect(b - 0.6, 0.1, 1.4, 2.8);
}
function staffPath(c, k) { const [l, o] = wlo(k), X = (x) => x * l + o; c.rect(X(-15), 0.55, X(23) - X(-15), 1.9); }
function staffDetail(c, t, p, view, k) {
  const [l, o] = wlo(k), cx = 27 * l + o, s = headSc(l);
  shp(c, t, PAL.GOLD, () => { c.arc(cx, 1.5, 5.4 * s, 0.32 * Math.PI, 1.68 * Math.PI); c.arc(cx + 2.6 * s, 1.5, 4.4 * s, 1.62 * Math.PI, 0.38 * Math.PI, true); c.closePath(); }, 1.6);
  const fl = p ? p.glow : 0, R = 2.9 * s * (1 + 0.25 * fl);
  shp(c, t, fl > 0.3 ? '#e9fbff' : PAL.ORB, () => c.arc(cx + 1.6 * s, 1.5, R, 0, 7), 1.5);
  c.fillStyle = t('#ffffff'); c.beginPath(); c.arc(cx + 0.6 * s, 0.4, R * 0.35, 0, 7); c.fill();
  c.fillStyle = t(PAL.GOLD); c.fillRect(22.4 * l + o - 1.6, 0, 1.8, 3);
}
function lancePath(c, k) {
  const [l, o] = wlo(k), X = (x) => x * l + o, s = headSc(l), h = headLen(l), b = X(40);
  c.rect(X(-13), 0.7, b - X(-13), 1.6); c.moveTo(b, 1.5 - 1.7 * s); c.lineTo(b + 10 * h, 1.5); c.lineTo(b, 1.5 + 1.7 * s); c.closePath();
  c.moveTo(X(4), -0.6); c.lineTo(X(7), 0.7); c.lineTo(X(7), 2.3); c.lineTo(X(4), 3.6); c.closePath();
}
function lanceDetail(c, t, p, view, k) {
  const [l, o] = wlo(k), s = headSc(l), h = headLen(l), b = 40 * l + o, w = Math.sin(performance.now() / 160) * 1.2;
  c.fillStyle = t(PAL.STEEL); c.beginPath(); c.moveTo(b, 1.5 - 1.7 * s); c.lineTo(b + 10 * h, 1.5); c.lineTo(b, 1.5 + 1.7 * s); c.closePath(); c.fill();
  c.fillStyle = t(PAL.GOLD); c.fillRect(b - 1, 0.2, 1.4, 2.6); c.beginPath(); c.moveTo(4 * l + o, -0.6); c.lineTo(7 * l + o, 0.7); c.lineTo(7 * l + o, 2.3); c.lineTo(4 * l + o, 3.6); c.closePath(); c.fill();
  const a = 31 * l + o, e = 38 * l + o;
  shp(c, t, PAL.VERMILION, () => { c.moveTo(a, 2.4); c.lineTo(e, 2.4); c.quadraticCurveTo(e - 2, 5.6 + w, e - 6 + w, 9.4 + w); c.quadraticCurveTo(a + 1, 6, a, 2.4); c.closePath(); }, 1.4);
}
// the shield stays upright whatever the forearm does (tilt from the pose); front face from the front, its inside from behind
function shieldDraw(c, t, p, view, k) {
  if (k.M) { const m = k.M.hB; c.translate(0, 1.5); c.rotate(-Math.atan2(m[1], m[0]) + (p ? p.tilt : 0) * D); }
  const s = p ? p.wl : 1; c.scale(s, s); c.translate(view === 'back' ? 0.6 : -0.6, 0);
  const rim = () => c.ellipse(0, 0, 10.4, 12.2, 0, 0, 7);
  if (view === 'back') {
    shp(c, t, PAL.WOOD, rim);
    c.save(); c.beginPath(); rim(); c.clip(); c.strokeStyle = t('#6e4527'); c.lineWidth = 0.7; c.beginPath(); for (const x of [-5, -1.7, 1.7, 5]) { c.moveTo(x, -12); c.lineTo(x, 12); } c.stroke();
    c.fillStyle = t(PAL.LEATHER); c.fillRect(-10, -3.6, 20, 2.2); c.fillRect(-10, 2.2, 20, 2.2); c.restore();
    c.strokeStyle = t(PAL.STEEL_DARK); c.lineWidth = 1.3; c.beginPath(); c.ellipse(0, 0, 9.6, 11.4, 0, 0, 7); c.stroke();
    return;
  }
  shp(c, t, PAL.VERMILION, rim);
  c.strokeStyle = t(PAL.GOLD); c.lineWidth = 1.4; c.beginPath(); c.ellipse(0, 0, 9.2, 11, 0, 0, 7); c.stroke();
  c.lineWidth = 0.7; c.beginPath(); c.ellipse(0, 0, 6.2, 7.4, 0, 0, 7); c.stroke();
  c.fillStyle = t(PAL.GOLD); c.beginPath(); for (let i = 0; i < 16; i++) { const r = i % 2 ? 2.6 : 4.8, a = i * Math.PI / 8; c.lineTo(r * Math.cos(a) * 0.86, r * Math.sin(a)); } c.closePath(); c.fill();
  shp(c, t, PAL.STEEL, () => c.arc(0, 0, 2.1, 0, 7), 1.4);
  c.fillStyle = t('#ffffff'); c.globalAlpha *= 0.5; c.beginPath(); c.ellipse(3.6, -6, 1.4, 2.6, 0.3, 0, 7); c.fill(); c.globalAlpha /= 0.5;
}
// the bow sits in the B hand; the arrow runs from the drawing hand through the grip (u). The limbs lie across u, or
// stand upright with bowUp (aiming at or away from the viewer, the arrow foreshortened); the belly (w) bulges along u.
// Not drawn (draw = 0), the bow hangs upright at the side.
function bowGeom(M, p) {
  const H = ap(M.hB, 0, 1.5), F = ap(M.hF, 0, 1.5); let ux = H[0] - F[0], uy = H[1] - F[1], d = Math.hypot(ux, uy);
  const dr = p ? p.draw : 0; if (d < 3 || dr < 0.05) { const w = dr < 0.05 ? 1 : 0; ux = lerp(ux / (d || 1), -1, w); uy = lerp(uy / (d || 1), 0, w); d = Math.hypot(ux, uy) || 1; }
  ux /= d; uy /= d;
  const up = p ? p.bowUp : 0, n0 = [uy, -ux], sg = n0[1] >= 0 ? 1 : -1; let n = [lerp(n0[0], 0, up), lerp(n0[1], sg, up)]; const nl = Math.hypot(...n) || 1; n = [n[0] / nl, n[1] / nl];
  let w = [-n[1], n[0]]; if (w[0] * ux + w[1] * uy < 0) w = [-w[0], -w[1]];
  return { H, F, u: [ux, uy], n, w, dr, R: 13 + (p && p.view === 'back' ? 1.5 : -1.5) * up };
}
function arrowShape(c, t, x, y, ux, uy, L) {
  const hx = x + ux * L, hy = y + uy * L, nx = uy, ny = -ux;
  c.lineCap = 'round'; c.beginPath(); c.moveTo(x, y); c.lineTo(hx, hy); c.strokeStyle = t(PAL.INK); c.lineWidth = 1.7; c.stroke(); c.strokeStyle = t(PAL.WOOD); c.lineWidth = 0.8; c.stroke();
  shp(c, t, PAL.STEEL, () => { c.moveTo(hx + ux * 3.4, hy + uy * 3.4); c.lineTo(hx + nx * 1.4, hy + ny * 1.4); c.lineTo(hx - nx * 1.4, hy - ny * 1.4); c.closePath(); }, 1.2);
  for (const s of [1, -1]) shp(c, t, PAL.VERMILION, () => { c.moveTo(x + ux * 1, y + uy * 1); c.lineTo(x + ux * 4.4, y + uy * 4.4); c.lineTo(x + ux * 0.4 + nx * s * 1.8, y + uy * 0.4 + ny * s * 1.8); c.closePath(); }, 1);
}
function bowDraw(c, t, p, view, k) {
  const g = bowGeom(k.M, p && Object.assign({}, p, { view })), [ux, uy] = g.u, [nx, ny] = g.n, [wx, wy] = g.w, H = g.H, R = g.R;
  const at = (a, b) => [H[0] + nx * a + wx * b, H[1] + ny * a + wy * b];
  const T1 = at(R, -2.4), T2 = at(-R, -2.4), N = [lerp(H[0] - ux * 3, g.F[0], g.dr), lerp(H[1] - uy * 3, g.F[1], g.dr)];
  c.lineCap = 'round'; c.beginPath(); c.moveTo(...T1); c.lineTo(...N); c.lineTo(...T2); c.strokeStyle = t(PAL.INK); c.lineWidth = 1.2; c.stroke(); c.strokeStyle = t(PAL.CREAM); c.lineWidth = 0.5; c.stroke();
  if (p && p.nock > 0.5) arrowShape(c, t, N[0], N[1], ux, uy, Math.max(p.bowUp > 0.5 ? 8 : 20, Math.hypot(H[0] - N[0], H[1] - N[1]) + 5));
  c.beginPath(); c.moveTo(...at(R + 0.6, 0.6)); c.bezierCurveTo(...at(R * 0.8, -5), ...at(4, 2.2), ...at(0, 1.6)); c.bezierCurveTo(...at(-4, 2.2), ...at(-R * 0.8, -5), ...at(-R - 0.6, 0.6));
  c.strokeStyle = t(PAL.INK); c.lineWidth = 3.4; c.stroke(); c.strokeStyle = t(PAL.WOOD); c.lineWidth = 1.9; c.stroke();
  c.strokeStyle = t(PAL.GOLD); c.lineWidth = 1.9; c.beginPath(); c.moveTo(...at(1.6, 1.8)); c.lineTo(...at(-1.6, 1.8)); c.stroke();
}
function quiverDraw(c, t, p, view) {
  c.save(); c.translate(-3.4, -2); c.rotate(0.55);
  for (const [x, col, h] of [[-1.4, PAL.VERMILION, 4.6], [0.4, PAL.CREAM, 5.4], [1.8, PAL.VERMILION, 4.2], [-0.2, PAL.CREAM, 3.8]]) shp(c, t, col, () => { c.moveTo(x, -19); c.lineTo(x - 1.2, -19 - h * 0.6); c.lineTo(x, -19 - h); c.lineTo(x + 1.2, -19 - h * 0.6); c.closePath(); }, 1.2);
  shp(c, t, PAL.LEATHER, () => { c.moveTo(-3, -19.5); c.lineTo(3, -19.5); c.lineTo(2.6, -1); c.quadraticCurveTo(0, 1, -2.6, -1); c.closePath(); });
  c.fillStyle = t(PAL.WOOD); c.fillRect(-3, -19.5, 6, 2.4); c.fillStyle = t(PAL.GOLD); c.fillRect(-2.8, -9, 5.6, 1.2);
  c.restore();
}

// ---- the horse (Kỵ): a simple separate rig in figure space. Its back sits under the rider's hips (p.hip), so
// the rider's bob, the gallop and a kneel (low hip) move it; its legs lift and shorten in a gallop like a run.
function horseRig(p) {
  const g = p ? p.hg : 0, ph = p ? p.hph : 0, sY = -(p ? p.hip : 31) - (p ? p.jump : 0);
  const lift = (off) => g * 6 * Math.max(0, Math.sin(2 * Math.PI * (ph + off)));
  return { x: p ? p.dx : 0, sY, lift, hl: p ? p.hl : 0, g, ph, bob: g * 1.2 * Math.sin(2 * Math.PI * (ph + 0.25)) };
}
function hleg(c, t, col, x, top, bot, w) {
  const len = Math.max(2.6, bot - top);
  shp(c, t, col, () => { c.moveTo(x - w / 2, top); c.lineTo(x + w / 2, top); c.lineTo(x + w * 0.38, top + len - 1); c.lineTo(x - w * 0.38, top + len - 1); c.closePath(); });
  shp(c, t, PAL.BOOT, () => c.rect(x - w * 0.46, top + len - 2.6, w * 0.92, 2.6));
}
const HORSE = {
  // seen from behind: rump, tail, hind legs; the far forelegs between them; the head is hidden beyond the rider
  headB() {},   // from behind the head is hidden by the rider
  foreB(c, t, p) { const h = horseRig(p); for (const [s, off] of [[-1, 0.5], [1, 0.65]]) hleg(c, t, PAL.HORSE_DARK, h.x + s * 3.6, h.sY + 12, -2.4 - h.lift(off), 3.4); },
  hindB(c, t, p) { const h = horseRig(p); for (const [s, off] of [[-1, 0], [1, 0.15]]) hleg(c, t, PAL.HORSE, h.x + s * 6.2, h.sY + 13, -h.lift(off), 4.4); },
  rumpB(c, t, p) {
    const h = horseRig(p), x = h.x, y = h.sY + h.hl * 1.5, sw = Math.sin(2 * Math.PI * h.ph) * h.g * 2.4 + Math.sin(performance.now() / 600) * 0.6;
    shp(c, t, PAL.VERMILION, () => { c.moveTo(x - 13.4, y - 1.6); c.lineTo(x + 13.4, y - 1.6); c.lineTo(x + 12.8, y + 5); c.lineTo(x - 12.8, y + 5); c.closePath(); });
    c.fillStyle = t(PAL.GOLD); c.fillRect(x - 13, y + 2.6, 26, 1.2);
    shp(c, t, PAL.HORSE, () => { c.moveTo(x, y + 2.4); c.bezierCurveTo(x - 3, y - 0.2, x - 12.6, y + 0.4, x - 12.6, y + 8); c.bezierCurveTo(x - 12.6, y + 15, x - 8, y + 18, x - 4, y + 18); c.lineTo(x + 4, y + 18); c.bezierCurveTo(x + 8, y + 18, x + 12.6, y + 15, x + 12.6, y + 8); c.bezierCurveTo(x + 12.6, y + 0.4, x + 3, y - 0.2, x, y + 2.4); c.closePath(); });
    c.fillStyle = t('#ffffff'); c.globalAlpha *= 0.3; c.beginPath(); c.ellipse(x + 7, y + 6, 2.6, 3.6, 0.3, 0, 7); c.fill(); c.globalAlpha /= 0.3;
    shp(c, t, PAL.HAIR, () => { c.moveTo(x - 2.2, y + 3); c.quadraticCurveTo(x - 3.4 + sw, y + 12, x - 1.8 + sw * 1.6, y + 22 - h.g * 3); c.lineTo(x + 2.4 + sw * 1.6, y + 21 - h.g * 3); c.quadraticCurveTo(x + 3.4 + sw, y + 12, x + 2.2, y + 3); c.closePath(); });
  },
  // seen from the front: far hind legs, saddle cloth, forelegs, chest with a red tassel, then the long face
  hindF(c, t, p) { const h = horseRig(p); for (const [s, off] of [[-1, 0], [1, 0.15]]) hleg(c, t, PAL.HORSE_DARK, h.x + s * 7.4, h.sY + 12, -2.4 - h.lift(off), 3.4); },
  saddleF(c, t, p) { const h = horseRig(p), x = h.x, y = h.sY; shp(c, t, PAL.VERMILION, () => c.rect(x - 13.6, y - 2, 27.2, 9)); c.fillStyle = t(PAL.GOLD); c.fillRect(x - 13.2, y + 4.6, 26.4, 1.2); },
  foreF(c, t, p) { const h = horseRig(p), y = h.sY - h.hl * 4; for (const [s, off] of [[-1, 0.5], [1, 0.65]]) hleg(c, t, PAL.HORSE, h.x + s * 5, y + 14, -h.lift(off) - h.hl * 3, 4.4); },
  chestF(c, t, p) {
    const h = horseRig(p), x = h.x, y = h.sY - h.hl * 4;
    shp(c, t, PAL.HORSE, () => { c.moveTo(x - 9.6, y + 1); c.quadraticCurveTo(x, y - 2, x + 9.6, y + 1); c.bezierCurveTo(x + 10.6, y + 10, x + 7, y + 17, x + 3, y + 17.4); c.lineTo(x - 3, y + 17.4); c.bezierCurveTo(x - 7, y + 17, x - 10.6, y + 10, x - 9.6, y + 1); c.closePath(); });
    c.strokeStyle = t(PAL.LEATHER); c.lineWidth = 1.7; c.beginPath(); c.moveTo(x - 9.8, y + 5); c.quadraticCurveTo(x, y + 10.5, x + 9.8, y + 5); c.stroke();
    c.fillStyle = t(PAL.GOLD); for (const k of [-6, -2, 2, 6]) { c.beginPath(); c.arc(x + k, y + 5 + 5.5 * (1 - (k / 9.8) ** 2) * 0.9, 0.7, 0, 7); c.fill(); }
    shp(c, t, PAL.VERMILION, () => { c.moveTo(x - 1.2, y + 9.4); c.lineTo(x + 1.2, y + 9.4); c.lineTo(x + 2.4, y + 15); c.lineTo(x - 2.4, y + 15); c.closePath(); }, 1.6);
  },
  headF(c, t, p) {
    // the horse faces the viewer: its neck rises from the chest and the long face hangs in front of the rider's lap
    const h = horseRig(p), hx = h.x - 1.5, hy = h.sY - 1 - h.hl * 6 + h.bob, cy = h.sY - h.hl * 4;
    shp(c, t, PAL.HORSE, () => { c.moveTo(h.x - 8, cy + 9); c.quadraticCurveTo(hx - 6.6, hy + 2, hx - 5, hy - 7); c.lineTo(hx + 5, hy - 7); c.quadraticCurveTo(hx + 6.6, hy + 2, h.x + 8, cy + 9); c.closePath(); });
    for (const e of [-3.6, 3.6]) shp(c, t, PAL.HORSE, () => { c.moveTo(hx + e - 1.7, hy - 8); c.lineTo(hx + e * 1.25, hy - 13.6); c.lineTo(hx + e + 1.7, hy - 8); c.closePath(); }, 1.8);
    shp(c, t, PAL.HORSE, () => { c.moveTo(hx - 5, hy - 7.4); c.quadraticCurveTo(hx, hy - 11.6, hx + 5, hy - 7.4); c.quadraticCurveTo(hx + 4.8, hy + 2, hx + 3.6, hy + 8.6); c.quadraticCurveTo(hx, hy + 10.4, hx - 3.6, hy + 8.6); c.quadraticCurveTo(hx - 4.8, hy + 2, hx - 5, hy - 7.4); c.closePath(); });
    c.fillStyle = t(PAL.CREAM); c.beginPath(); c.moveTo(hx - 1.1, hy - 7); c.lineTo(hx + 1.1, hy - 7); c.lineTo(hx + 0.8, hy + 4); c.lineTo(hx - 0.8, hy + 4); c.closePath(); c.fill();
    shp(c, t, PAL.MUZZLE, () => c.ellipse(hx, hy + 8, 4, 2.9, 0, 0, 7), 1.6);
    c.fillStyle = t(PAL.INK); for (const s of [-1, 1]) { c.beginPath(); c.ellipse(hx + s * 1.7, hy + 8.4, 0.65, 0.95, 0, 0, 7); c.fill(); c.beginPath(); c.ellipse(hx + s * 3.3, hy - 2.6, 0.9, 1.3, 0, 0, 7); c.fill(); }
    c.strokeStyle = t(PAL.LEATHER); c.lineWidth = 0.9; c.beginPath(); c.moveTo(hx - 4.2, hy + 4.6); c.lineTo(hx + 4.2, hy + 4.6); c.moveTo(hx - 4.8, hy - 5); c.lineTo(hx - 4.2, hy + 4.6); c.moveTo(hx + 4.8, hy - 5); c.lineTo(hx + 4.2, hy + 4.6); c.stroke();
    shp(c, t, PAL.HAIR, () => { c.moveTo(hx - 2.8, hy - 9.6); c.quadraticCurveTo(hx, hy - 12.6, hx + 2.8, hy - 9.6); c.lineTo(hx + 0.8, hy - 5); c.lineTo(hx - 1, hy - 6); c.closePath(); }, 1.4);
    c.fillStyle = t(PAL.GOLD); for (const s of [-1, 1]) { c.beginPath(); c.arc(hx + s * 4.2, hy + 4.6, 0.8, 0, 7); c.fill(); }
  },
};
const horsePieces = () => [
  { id: 'h_headB', bone: 'world', z: { front: null, back: -1 }, draw: HORSE.headB },
  { id: 'h_foreB', bone: 'world', z: { front: null, back: -0.6 }, draw: HORSE.foreB },
  { id: 'h_hindB', bone: 'world', z: { front: null, back: 2.5 }, draw: HORSE.hindB },
  { id: 'h_rumpB', bone: 'world', z: { front: null, back: 3 }, draw: HORSE.rumpB },
  { id: 'h_hindF', bone: 'world', z: { front: -1, back: null }, draw: HORSE.hindF },
  { id: 'h_saddleF', bone: 'world', z: { front: -0.6, back: null }, draw: HORSE.saddleF },
  { id: 'h_foreF', bone: 'world', z: { front: 1.2, back: null }, draw: HORSE.foreF },
  { id: 'h_chestF', bone: 'world', z: { front: 1.5, back: null }, draw: HORSE.chestF },
  { id: 'h_headF', bone: 'world', z: { front: 4.6, back: null }, draw: HORSE.headF },
];

// ---- classes. Each takes the Kiếm pieces, swaps or drops some, adds its own; poses come from the generic clips
// passed through `fit` (class constants such as a two-handed grip or riding), plus its own clips where needed.
const kit = (set, drop = [], add = []) => PIECES.filter((q) => !drop.includes(q.id)).map((q) => set[q.id] ? Object.assign({}, q, set[q.id]) : q).concat(add);
const CLS = {};
function defClass(id, name, pieces, o) {
  const C = Object.assign({ id, name, pieces, fit: null, rest: {}, clips: {}, walk: null, tip: () => [27, 11], glowAt: (M) => ap(M.hF, 13, 1.5), hitT: [0.26, 0.56], aimB: false, mount: false }, o);
  C.F = (q) => C.fit ? Object.assign({}, q, C.fit(q)) : q;
  const r = (k, g) => { const v = C.rest[k]; return v ? (v.back ? v : { back: v, front: v }) : { back: C.F(g), front: C.F(g) }; };
  C.R = { idle: r('idle', IDLE), stance: r('stance', STANCE) }; C.cache = {};
  CLS[id] = C; return C;
}
function clipOf(C, name, view) {
  const key = name + view; if (C.cache[key]) return C.cache[key];
  let cl = C.clips[name]; if (cl && !Array.isArray(cl)) cl = cl[view];
  if (!cl) cl = CLIPS[name].map(([d, e, q]) => [d, e, q === STANCE ? C.R.stance[view] : q === IDLE ? C.R.idle[view] : C.F(q)]);
  return (C.cache[key] = cl);
}
const with_ = (q, o) => P(Object.assign({}, q, o));
const tipAt = (x0, x1) => (p) => [x0 * p.wl + p.wo, x1 * p.wl + p.wo];

defClass('kiem', 'Kiếm', PIECES, {});

// Khiên: the shield stays between the unit and the enemy: low in front of the off side (seen from the front), beyond
// the body with its rim showing at the off side (from behind). Shove = lunge along the board, shield a little nearer
// the enemy (bigger from the front, smaller and higher from behind), then a short cut. A hit braces the shield.
(() => {
  const shB = (E, H, o) => Object.assign(armTo('B', E, H), { tilt: 0 }, o);
  const holdF = shB([-9, -6.5], [-3, 0]), holdBk = shB([-9.5, -9], [-3.5, -5]);
  const st = P(Object.assign({ torso: 3, head: -2, uaF: -26, laF: -76, blade: -62, hip: 26, fF: 5.6, fB: -5.6 }, holdF));
  const stBk = with_(st, holdBk);
  const shoveU = P(Object.assign({ torso: -6, head: -3, uaF: -14, laF: -40, blade: 50, hip: 26.6, fF: 5, fB: -5, dx: 5 }, shB([-9.5, -11], [-3.5, -8.5], { wl: 0.9 })));
  const shoveD = P(Object.assign({ torso: -6, head: 3, uaF: -14, laF: -40, blade: 50, hip: 24.4, fF: 6.4, fB: -6.4, dx: 5 }, shB([-9, -5], [-3, 2.6], { wl: 1.12 })));
  const cutU = with_(shoveU, { head: -4, uaF: -176, laF: -24, blade: -118, hip: 26.8, dx: 5.5, trail: 1, wl: 0.94 });
  const cutD = with_(shoveD, { torso: -7, head: 4, uaF: 20, laF: 16, blade: -240, hip: 24, dx: 5.5, trail: 1, wl: 1.08 });
  const brace = (hold, wl) => P(Object.assign({ torso: -8, head: 6, uaF: -24, laF: -50, blade: -40, hip: 24.6, fF: 4, fB: -6.6, dx: -3, eyes: 1, flash: 1 }, shB([hold.E[0], hold.E[1] - 2], [hold.H[0] + 0.5, hold.H[1] - 3.5], { wl })));
  const at = (st, sh, cut) => [[0.12, 'out', with_(st, { torso: 6, uaF: -10, laF: -30, blade: 60, hip: 24.6 })], [0.1, 'in', sh], [0.1, 'out', cut], [0.12, 'lin', with_(cut, { trail: 0 })], [0.26, 'io', st]];
  const sk = (st, sh, cut) => [[0.3, 'out', with_(st, { hip: 23.4, glow: 1 })], [0.12, 'in', with_(sh, { glow: 1, dx: 8 })], [0.12, 'out', with_(cut, { glow: 1, dx: 8.5 })], [0.2, 'lin', with_(cut, { glow: 0.4, dx: 8.5, trail: 0 })], [0.32, 'io', st]];
  const hitC = (st, r) => [[0.07, 'out', r], [0.16, 'lin', with_(r, { flash: 0 })], [0.26, 'io', st]];
  const rF = brace({ E: [-9, -6.5], H: [-3, 0] }, 1.06), rB = brace({ E: [-9.5, -9], H: [-3.5, -5] }, 0.96);
  defClass('khien', 'Khiên', kit({ head: { detail: helmHead({ iron: true, cheeks: true }) }, torso: { detail: torsoKit({ armor: 'lamellar', strap: true }) }, pauldron: { col: PAL.IRON }, pauldronB: { col: PAL.IRON } }, [],
    [{ id: 'shield', name: 'Khiên', bone: 'hB', z: { front: 4.5, back: -0.5 }, draw: shieldDraw }]), {
    rest: { stance: { back: stBk, front: st }, idle: { back: P(Object.assign({ uaF: -9, laF: -6, blade: 56 }, holdBk)), front: P(Object.assign({ uaF: -9, laF: -6, blade: 56 }, holdF)) } },
    clips: { attackUp: at(stBk, shoveU, cutU), attackDown: at(st, shoveD, cutD), skillUp: sk(stBk, shoveU, cutU), skillDown: sk(st, shoveD, cutD), hit: { back: hitC(stBk, rB), front: hitC(st, rF) } },
    walk: (ph, view) => with_(walkPose(ph), view === 'back' ? holdBk : holdF),
    hitT: [0.32, 0.54],
  });
})();

// Thương: long willow-leaf spear in both hands, rear (F) hand at the hip, front (B) hand a forearm further along the
// shaft. Ready toward the enemy: from behind the spear points up the board at the sword side, from the front it points
// at the viewer (short shaft, big head). The thrust drives both hands along the board axis.
(() => {
  const sp = (rear, front, eF, wl, o) => { const bl = Math.atan2(front[1] - rear[1], front[0] - rear[0]) / D;
    return P(Object.assign({ hip: 26, fF: 5.6, fB: -5.6, torso: 3, head: -2, blade: bl, wl, wo: 0, gw: 1, grip: Math.hypot(front[0] - rear[0], front[1] - rear[1]) / wl }, armTo('F', eF, rear, bl), o)); };
  const stB = sp([7.4, -0.5], [8.8, -10.5], [11.5, -6.5], 0.9), stF = sp([5.5, -6.5], [0.8, -0.8], [10.5, -9], 0.5);
  const pullB = sp([7.4, 1.5], [8.6, -8.5], [11.8, -4], 0.9, { torso: 6, hip: 24.4, fF: 6.4, fB: -6.4 });
  const pullF = sp([6.5, -8.5], [1.6, -2.5], [11, -11], 0.6, { torso: 6, hip: 24.4, fF: 6.4, fB: -6.4 });
  const thB = sp([7, -9.5], [8, -19.5], [10.8, -14], 0.86, { torso: -6, head: -4, wo: 5, hip: 26.8, fF: 5, fB: -5, dx: 6, trail: 1 });
  const thF = sp([4.5, -2.5], [0, 2.6], [9.5, -5.5], 0.4, { torso: -7, head: 4, wo: 2, hip: 24, fF: 6.4, fB: -6.4, dx: 6, trail: 1 });
  const at = (st, pull, th) => [[0.16, 'out', pull], [0.08, 'in', th], [0.14, 'lin', with_(th, { trail: 0 })], [0.26, 'io', st]];
  const sk = (st, pull, th) => [[0.32, 'out', with_(pull, { glow: 1, hip: 23.2 })], [0.1, 'in', with_(th, { glow: 1, dx: 9, wo: th.wo + 3, jump: 3 })], [0.2, 'lin', with_(th, { glow: 0.4, dx: 9, wo: th.wo + 3, trail: 0 })], [0.32, 'io', st]];
  const hitC = (st) => [[0.07, 'out', with_(st, { torso: -9, head: -8, hip: 25.2, dx: -3.5, eyes: 1, flash: 1 })], [0.13, 'lin', with_(st, { torso: -8, head: -8, hip: 25.2, dx: -3.5, eyes: 1 })], [0.26, 'io', st]];
  const carry = { gw: 0, uaF: -8, laF: -28, blade: -94 };
  defClass('thuong', 'Thương', kit({ head: { detail: nonTran }, torso: { detail: torsoKit({ armor: 'quilt', scarf: false }) } }, ['sword', 'pauldron', 'pauldronB'],
    [{ id: 'spear', name: 'Thương', bone: 'hF', z: { front: 3.5, back: 3 }, col: PAL.WOOD, path: spearPath, detail: spearDetail }]), {
    fit: (q) => ({ gw: 0 }),
    rest: { stance: { back: stB, front: stF }, idle: P(Object.assign({ uaB: 12, laB: -12 }, carry)) },
    clips: { attackUp: at(stB, pullB, thB), attackDown: at(stF, pullF, thF), skillUp: sk(stB, pullB, thB), skillDown: sk(stF, pullF, thF), hit: { back: hitC(stB), front: hitC(stF) } },
    walk: (ph) => with_(walkPose(ph), Object.assign({}, carry, { blade: -86 + 4 * Math.sin(2 * Math.PI * ph) })),
    tip: tipAt(44, 30), glowAt: (M, p) => ap(M.hF, 38 * p.wl + p.wo, 1.5), hitT: [0.24, 0.42],
  });
})();

// Cung: hood, quiver, recurve bow in the B hand. Aim runs along the board: from the front the bow stands upright in
// front of the chest, the bow arm short (pointing at the viewer), the draw hand at the cheek, the arrow short with its
// head toward the viewer; from behind the bow is raised beyond the head (upper limb above the off shoulder), the draw
// elbow out on the sword side. Stance = half drawn; attack = full draw, hold, release. Idle and run carry it low.
(() => {
  const aim = (bE, bH, fE, fH, o) => P(Object.assign({ torso: 2, hip: 26, fF: 5.6, fB: -5.6, draw: 1, nock: 1, bowUp: 1 }, armTo('B', bE, bH), armTo('F', fE, fH), o));
  const bF = [[-3.8, -12.6], [-1.4, -9.6]], bB = [[-6, -24.5], [-6, -34]];
  const stF = aim(...bF, [11, -11], [5, -17], { head: 4 }), fullF = aim(...bF, [12.2, -14.6], [5.8, -19.6], { head: 4, hip: 25.4 });
  const relF = aim(...bF, [12, -18.5], [13, -26.5], { head: 4, hip: 25.4, draw: 0, nock: 0 });
  const stB = aim(...bB, [12, -13], [4.4, -19.4], { head: -4 }), fullB = aim(...bB, [12.6, -15.6], [4.2, -21.6], { head: -5, hip: 25.4 });
  const relB = aim(...bB, [13, -17], [13.4, -26], { head: -5, hip: 25.4, draw: 0, nock: 0 });
  // relaxed arms: bow hanging upright by the off hip, the other hand loose by the sword hip
  const low = (sw = 0) => Object.assign(armTo('B', [-8.4, -6 - sw], [-7.6, 2.6 - sw * 1.6]), { draw: 0, nock: 0, bowUp: 0 });
  const loose = (sw = 0) => armTo('F', [8.6, -6.2 + sw], [6.8 - sw, 1.8 + sw * 1.6]);
  const at = (st, full, rel) => [[0.22, 'out', full], [0.1, 'lin', full], [0.06, 'out', rel], [0.22, 'lin', rel], [0.3, 'io', st]];
  const sk = (st, full, rel) => [[0.3, 'out', with_(full, { glow: 1, hip: 24.4 })], [0.3, 'lin', with_(full, { glow: 1, hip: 24.2 })], [0.06, 'out', with_(rel, { glow: 0.6 })], [0.26, 'lin', with_(rel, { glow: 0.2 })], [0.32, 'io', st]];
  defClass('cung', 'Cung', kit({ head: { detail: hood }, torso: { detail: torsoKit({ armor: 'vest', belt2: true }) } }, ['sword', 'pauldron', 'pauldronB'],
    [{ id: 'quiver', name: 'Ống tên', bone: 'torso', z: { front: 1.5, back: 5.5 }, draw: quiverDraw },
      { id: 'bow', name: 'Cung', bone: 'world', z: { front: 4.5, back: 0.5 }, draw: bowDraw }]), {
    // generic hit / die keep the arms in close; the cheer still raises them
    fit: (q) => q.uaB > 100 ? { nock: 0, draw: 0, bowUp: 0 } : Object.assign(low(), loose()),
    rest: { stance: { back: stB, front: stF }, idle: P(Object.assign(low(), loose())) },
    clips: { attackUp: at(stB, fullB, relB), attackDown: at(stF, fullF, relF), skillUp: sk(stB, fullB, relB), skillDown: sk(stF, fullF, relF) },
    walk: (ph) => { const s = Math.sin(2 * Math.PI * ph); return with_(walkPose(ph), Object.assign(low(0.6 * s), loose(1.6 * s))); },
    tip: () => [0, 0], glowAt: (M) => ap(M.hB, 0, 1.5), aimB: true, shot: 'arrow', release: [0.32, 0.6],
    muzzle: (M, p, view) => { const g = bowGeom(M, p); return { pt: [g.H[0] + g.u[0] * 4, g.H[1] + g.u[1] * 4], dir: view === 'back' ? [-0.06, -1] : [-0.22, 1] }; },
  });
})();

// Pháp: long robe, drooping hat, staff with a crescent holding an orb. Attack = raise staff, orb flares, bolt.
(() => {
  const st = P({ torso: 2, head: -2, uaF: -22, laF: -74, blade: -96, uaB: 20, laB: -38, hip: 26, fF: 5.6, fB: -5.6 });
  const up = with_(st, { uaF: -168, laF: -6, blade: -94, head: -4, glow: 0.8, hip: 26.8 });
  const fwB = with_(up, { uaF: -150, laF: -10, blade: -76, glow: 0.3, dx: 2 }), fwF = with_(st, { uaF: -46, laF: -14, blade: 42, wl: 0.8, glow: 0.3, dx: 2, head: 4 });
  const at = (fw) => [[0.28, 'out', up], [0.12, 'lin', up], [0.08, 'out', fw], [0.22, 'lin', with_(fw, { glow: 0 })], [0.28, 'io', st]];
  const sk = (fw) => [[0.36, 'out', with_(up, { glow: 1, jump: 2 })], [0.24, 'lin', with_(up, { glow: 1, jump: 2.4 })], [0.08, 'out', with_(fw, { glow: 1 })], [0.26, 'lin', with_(fw, { glow: 0.3 })], [0.32, 'io', st]];
  const robe = { col: PAL.PLUM, path: (c) => { c.moveTo(-6.4, -1); c.lineTo(6.4, -1); c.lineTo(9.8, 20.6); c.quadraticCurveTo(0, 22.6, -9.8, 20.6); c.closePath(); },
    detail: (c, t) => { c.strokeStyle = t(PAL.GOLD); c.lineWidth = 1.2; c.beginPath(); c.moveTo(-9.4, 19); c.quadraticCurveTo(0, 21, 9.4, 19); c.stroke(); c.strokeStyle = t(PAL.PLUM_DARK); c.lineWidth = 0.8; c.beginPath(); c.moveTo(1.2, 1); c.lineTo(1.6, 20); c.moveTo(-4, 2); c.lineTo(-6, 19); c.stroke(); } };
  defClass('phap', 'Pháp', kit({ head: { detail: mageHat }, torso: { col: PAL.PLUM, detail: torsoKit({ armor: 'robe' }) }, skirt: Object.assign({ name: 'Áo bào' }, robe), uaF: { col: PAL.PLUM }, uaB: { col: dark(PAL.PLUM) } }, ['sword', 'pauldron', 'pauldronB'],
    [{ id: 'staff', name: 'Gậy phép', bone: 'hF', z: { front: 5, back: 3 }, col: PAL.WOOD, path: staffPath, detail: staffDetail }]), {
    rest: { stance: st, idle: P({ uaF: -10, laF: -40, blade: -94, uaB: 12, laB: -12 }) },
    clips: { attackUp: at(fwB), attackDown: at(fwF), skillUp: sk(fwB), skillDown: sk(fwF) },
    walk: (ph) => with_(walkPose(ph), { blade: -88 + 5 * Math.sin(2 * Math.PI * ph), uaF: -12, laF: -40 }),
    tip: tipAt(30, 22), glowAt: (M, p) => ap(M.hF, 28.6 * p.wl + p.wo, 1.5), shot: 'bolt', release: [0.42, 0.66],
    muzzle: (M, p, view) => ({ pt: ap(M.hF, 28.6 * p.wl + p.wo, 1.5), dir: view === 'back' ? [0.1, -1] : [-0.42, 0.9] }),
  });
})();

// Kỵ: a rider on a horse, lance couched; the generic clips are fitted to a seated rider (legs astride, no jumps)
(() => {
  const seat = { ik: 0, ride: 1, thF: -60, shF: 60, thB: 60, shB: -60, ftF: 0, ftB: 0, flat: 1, stF: 0, stB: 0 };
  const fit = (q) => Object.assign({}, seat, { hip: 31 + (q.hip - 26) * 0.5, jump: 0, hl: q.jump / 6, dx: q.root ? q.dx : q.dx * 1.2 });
  const S = (o) => P(Object.assign({}, seat, { hip: 31 }, o));
  const stB = S({ torso: 3, uaF: -28, laF: -54, blade: -76, uaB: 22, laB: -64 }), stF = S({ torso: 3, uaF: -20, laF: -66, blade: 30, uaB: 22, laB: -64 });
  const pullB = with_(stB, { torso: 6, uaF: -6, laF: -40, blade: -70, wo: -5, hip: 30.4 }), pullF = with_(stF, { torso: 6, uaF: -4, laF: -56, blade: 26, wo: -5, hip: 30.4 });
  const thB = with_(stB, { torso: -6, head: -3, uaF: -160, laF: -12, blade: -88, wl: 0.9, wo: 9, dx: 7, trail: 1 }), thF = with_(stF, { torso: -8, head: 4, uaF: -56, laF: -22, blade: 50, wl: 0.72, wo: 9, dx: 7, trail: 1 });
  const at = (st, pull, th) => [[0.16, 'out', pull], [0.08, 'in', th], [0.14, 'lin', with_(th, { trail: 0 })], [0.26, 'io', st]];
  const sk = (st, pull, th) => [[0.32, 'out', with_(pull, { glow: 1, hl: 0.8 })], [0.1, 'in', with_(th, { glow: 1, dx: 11, wo: th.wo + 4 })], [0.2, 'lin', with_(th, { glow: 0.4, dx: 11, wo: th.wo + 4, trail: 0 })], [0.32, 'io', st]];
  const slump = S({ torso: 16, head: 18, uaF: -14, laF: -30, blade: 20, uaB: 10, laB: -20, hip: 29, eyes: 1, flash: 0.6 }), down = S({ torso: 30, head: 24, uaF: -6, laF: -10, blade: 40, uaB: 6, laB: -6, hip: 22, eyes: 1 });
  defClass('ky', 'Kỵ', kit({ head: { detail: helmHead({ feathers: true }) }, torso: { detail: torsoKit({ armor: 'plate', scarf: true }) } }, ['sword'],
    [{ id: 'lance', name: 'Giáo dài', bone: 'hF', z: { front: 5, back: 3 }, col: PAL.WOOD, path: lancePath, detail: lanceDetail }].concat(horsePieces())), {
    fit, mount: true,
    rest: { stance: { back: stB, front: stF }, idle: S({ uaF: -8, laF: -24, blade: -92, uaB: 22, laB: -64 }) },
    clips: { attackUp: at(stB, pullB, thB), attackDown: at(stF, pullF, thF), skillUp: sk(stB, pullB, thB), skillDown: sk(stF, pullF, thF),
      die: [[0.26, 'out', slump], [0.4, 'in', down], [0.5, 'lin', down], [0.5, 'lin', with_(down, { alpha: 0 })], [0.6, 'lin', with_(down, { alpha: 0, hip: 31, torso: 0, head: 0 })], [0.3, 'lin', S({ uaF: -8, laF: -24, blade: -92, uaB: 22, laB: -64 })]] },
    walk: (ph, view) => { const s = Math.sin(2 * Math.PI * ph); return S({ torso: 6 + 2 * s, head: -2, uaF: -24, laF: -56, blade: view === 'back' ? -78 : 30, uaB: 24, laB: -70, hip: 31 + 1.2 * Math.sin(2 * Math.PI * (ph + 0.25)), hg: 1, hph: ph }); },
    tip: tipAt(50, 32), glowAt: (M, p) => ap(M.hF, 44 * p.wl + p.wo, 1.5),
  });
  CLS.ky.clips.fall = CLS.ky.clips.die.slice(0, 4);
})();
const CLASS_IDS = ['kiem', 'khien', 'thuong', 'cung', 'phap', 'ky'];

// ---- draw the whole figure at (ox, oy) with a scale. opt.view: 'front' (enemy) or 'back' (player); opt.cls: class id
function zOrder(C, view) {
  const key = 'z' + view; if (C.cache[key]) return C.cache[key];
  const zs = [...new Set(C.pieces.filter((q) => q.z[view] != null).map((q) => q.z[view]))].sort((a, b) => a - b);
  return (C.cache[key] = zs.map((z) => C.pieces.filter((q) => q.z[view] === z)));
}
function drawFigure(c, p, M, ox, oy, sc, opt) {
  const C = CLS[opt.cls || 'kiem'], flash = p.flash, view = opt.view || 'front', t = (col) => flash > 0.02 ? mix(col, '#ffffff', flash * 0.8) : col;
  c.save(); c.translate(ox, oy); c.scale(opt.flip ? -sc : sc, sc);
  const rx = M.root[4];
  c.globalAlpha = p.alpha;
  if (!opt.noShadow) { c.fillStyle = 'rgba(43,35,32,0.22)'; c.beginPath(); c.ellipse(rx, 0.6, (C.mount ? 15 : 11) - Math.min(4, p.jump * 0.5), 2.6, 0, 0, 7); c.fill(); }
  if (opt.trail && opt.trail.length > 1) drawTrail(c, opt.trail);
  if (p.glow > 0.02) { const g = C.glowAt(M, p), gr = c.createRadialGradient(g[0], g[1], 1, g[0], g[1], 20); gr.addColorStop(0, `rgba(255,224,102,${0.75 * p.glow})`); gr.addColorStop(1, 'rgba(255,224,102,0)'); c.fillStyle = gr; c.beginPath(); c.arc(g[0], g[1], 20, 0, 7); c.fill(); }
  c.lineJoin = 'round';
  const K = (q) => ({ s: M.S[q.bone] || 1, view, heel: M.heel[q.bone] || 0, p, M });
  for (const set of zOrder(C, view)) {
    for (const q of set) { if (q.draw) continue; c.save(); c.transform(...M[q.bone]); c.beginPath(); q.path(c, K(q)); c.strokeStyle = t(PAL.INK); c.lineWidth = 2.2; c.stroke(); c.restore(); }
    for (const q of set) { c.save(); c.transform(...M[q.bone]); if (q.draw) q.draw(c, t, p, view, K(q)); else { c.beginPath(); q.path(c, K(q)); c.fillStyle = t(q.col); c.fill(); if (q.detail) q.detail(c, t, p, view, K(q)); } c.restore(); }
  }
  if (opt.bones) drawBones(c, M);
  c.restore();
}
function drawBones(c, M) {
  c.globalAlpha = 1; c.lineCap = 'round';
  const J = {}; for (const [n] of BONES) J[n] = ap(M[n], 0, 0);
  const tips = { head: ap(M.head, 0, -12), hF: ap(M.hF, 26, 1.5), hB: ap(M.hB, 0, 3), ftF: ap(M.ftF, 0, ANKLE), ftB: ap(M.ftB, 0, ANKLE) };
  const seg = (a, b) => { c.strokeStyle = '#1b2035'; c.lineWidth = 1.5; c.beginPath(); c.moveTo(...a); c.lineTo(...b); c.stroke(); c.strokeStyle = '#ffe066'; c.lineWidth = 0.8; c.beginPath(); c.moveTo(...a); c.lineTo(...b); c.stroke(); };
  for (const [n, par] of BONES) if (par && par !== 'root' && par !== 'torso') seg(J[par], J[n]);
  seg(J.root, J.head); seg(J.uaB, J.uaF); seg(J.thB, J.thF);
  for (const k in tips) seg(J[k], tips[k]);
  for (const [n] of BONES) { if (n === 'torso') continue; c.fillStyle = '#1b2035'; c.beginPath(); c.arc(J[n][0], J[n][1], 1.5, 0, 7); c.fill(); c.fillStyle = (n in LIMIT && n !== 'head') ? '#ff5a3c' : '#ffe066'; c.beginPath(); c.arc(J[n][0], J[n][1], 1, 0, 7); c.fill(); }
}
function drawTrail(c, tr) {
  for (let i = 1; i < tr.length; i++) {
    const a = tr[i - 1], b = tr[i], al = (i / tr.length) * 0.75 * b.w;
    c.fillStyle = `rgba(255,250,235,${al})`; c.beginPath(); c.moveTo(...a.tip); c.lineTo(...b.tip); c.lineTo(...b.mid); c.lineTo(...a.mid); c.closePath(); c.fill();
  }
}
// projectiles in screen space: an arrow (slight arc) or a bolt (glowing orb with a tail)
function drawShot(c, s, x, y, vx, vy, k) {
  const l = Math.hypot(vx, vy) || 1, ux = vx / l, uy = vy / l, sc = s.sc;
  c.save(); c.translate(x, y); c.scale(sc, sc);
  if (s.kind === 'arrow') arrowShape(c, (q) => q, -ux * 20, -uy * 20, ux, uy, 20);
  else {
    const r = s.big ? 5.5 : 3.6;
    for (let i = 5; i >= 1; i--) { c.fillStyle = `rgba(143,230,255,${0.12 * (6 - i) / 5})`; c.beginPath(); c.arc(-ux * i * 3.2, -uy * i * 3.2, r * (1 - i * 0.12), 0, 7); c.fill(); }
    const g = c.createRadialGradient(0, 0, 0.5, 0, 0, r * 2.6); g.addColorStop(0, 'rgba(255,250,220,0.9)'); g.addColorStop(1, s.big ? 'rgba(255,224,102,0)' : 'rgba(143,230,255,0)'); c.fillStyle = g; c.beginPath(); c.arc(0, 0, r * 2.6, 0, 7); c.fill();
    c.fillStyle = '#e9fbff'; c.strokeStyle = PAL.INK; c.lineWidth = 1.1; c.beginPath(); c.arc(0, 0, r * 0.7, 0, 7); c.fill(); c.stroke();
  }
  c.restore();
}

// ---- actors: each plays clips of key poses and falls back to idle or stance
function restOf(A) { const C = CLS[A.cls]; return C.R[A.stance ? 'stance' : 'idle'][A.view]; }
function makeActor(stance, view, cls = 'kiem') { const A = { cur: null, from: null, queue: [], t: 0, walk: 0, phase: 0, clock: Math.random() * 5, trail: [], stance, hold: false, view, cls }; A.from = restOf(A); A.cur = P(A.from); return A; }
function play(A, name, dur) {
  A.trail = []; A.hold = name === 'fall';
  if (name === 'walk') { A.walk = dur || 1.6; A.queue = []; A.from = A.cur; A.t = 0; return; }
  if (name === 'attack' || name === 'skill') name += A.view === 'back' ? 'Up' : 'Down';
  A.walk = 0; A.from = A.cur; A.t = 0; A.queue = clipOf(CLS[A.cls], name, A.view).slice();
}
function update(A, dt) {
  const C = CLS[A.cls], rest = restOf(A); A.clock += dt;
  if (A.walk > 0) {
    A.walk -= dt; A.t += dt; A.phase += dt * (C.mount ? 2.6 : 3.2);
    A.cur = blend(A.from, C.walk ? C.walk(A.phase, A.view) : C.F(walkPose(A.phase)), EASE.io(Math.min(1, A.t / 0.18)));
    if (A.walk <= 0) { A.from = A.cur; A.t = 0; A.queue = [[0.22, 'io', rest]]; }
  } else if (A.queue.length) {
    const [dur, ease, to] = A.queue[0]; A.t += dt;
    A.cur = blend(A.from, to, EASE[ease](Math.min(1, A.t / dur)));
    if (A.t >= dur) { A.from = to; A.cur = P(to); A.t -= dur; A.queue.shift(); }
  } else if (!A.hold) {
    if (A.from !== rest) { A.queue = [[0.3, 'io', rest]]; A.t = 0; A.from = A.cur; }
    else { const b = Math.sin(A.clock * 2.4); A.cur = P(Object.assign({}, rest, { torso: rest.torso + 0.8 * b, head: rest.head - 0.6 * b, hip: rest.hip - 0.25 * (1 + b), uaF: rest.uaF + 1.5 * b, uaB: rest.uaB - 1.5 * b, blade: rest.blade + 1.5 * Math.sin(A.clock * 2.4 - 0.6), eyes: (A.clock % 3.4) < 0.12 ? 1 : 0 })); }
  }
  const M = solve(A.cur, A.view);
  if (A.cur.trail > 0.03) { const [tx, mx] = C.tip(A.cur); A.trail.push({ tip: ap(M.hF, tx, 1.5), mid: ap(M.hF, mx, 1.5), w: 1 }); }
  else for (const s of A.trail) s.w -= dt * 7;
  A.trail = A.trail.filter((s) => s.w > 0).slice(-14);
  return M;
}

// ---- stage: the same unit from behind (ours) and from the front (the enemy's), driven by the same buttons
let stageCls = 'kiem';
const pair = [makeActor(true, 'back'), makeActor(true, 'front')];
const stage = document.getElementById('stage'), sx = stage.getContext('2d');
let showBones = true, slow = false, last = performance.now(), clockS = 0, stageEv = [], stageShots = [];
const STX = [180, 520], GY = 520, SSC = 4.5;
function frame(now) {
  const real = Math.min(0.05, (now - last) / 1000); last = now; const dt = slow ? real * 0.25 : real;
  const W = stage.width, H = stage.height, gy = GY, C = CLS[stageCls], sc = SSC * (C.mount ? 0.9 : 1);
  clockS += dt; while (stageEv.length && stageEv[0].at <= clockS) stageEv.shift().fn();
  sx.clearRect(0, 0, W, H);
  sx.fillStyle = '#d7c093'; sx.fillRect(0, gy, W, H - gy);
  sx.fillStyle = PAL.INK; sx.fillRect(0, gy, W, 3);
  sx.font = '800 24px "Be Vietnam Pro", system-ui, sans-serif'; sx.textAlign = 'center';
  pair.forEach((A, i) => { const x = STX[i], M = update(A, dt); drawFigure(sx, A.cur, M, x, gy, sc, { bones: showBones, trail: A.trail, view: A.view, cls: A.cls }); sx.fillStyle = PAL.INK; sx.fillText(i ? 'QUÂN ĐỊCH · NHÌN TỪ MẶT' : 'QUÂN TA · NHÌN TỪ LƯNG', x + 10, gy + 44); });
  for (const s of stageShots) { s.t += dt; s.x += s.vx * dt; s.y += s.vy * dt; sx.globalAlpha = clamp((s.life - s.t) / 0.15, 0, 1); drawShot(sx, s, s.x, s.y, s.vx, s.vy); sx.globalAlpha = 1; }
  stageShots = stageShots.filter((s) => s.t < s.life);
  boardTick(real);
  requestAnimationFrame(frame);
}
// a ranged attack on the stage lets its arrow or bolt fly off toward where the enemy would be
function stageFire(A, i, skill) {
  const C = CLS[A.cls]; if (!C.shot) return;
  stageEv.push({ at: clockS + C.release[skill ? 1 : 0], fn: () => {
    const M = solve(A.cur, A.view), m = C.muzzle(M, A.cur, A.view), sc = SSC, l = Math.hypot(...m.dir);
    for (const a of skill && C.shot === 'arrow' ? [-0.14, 0, 0.14] : [0]) {
      const ca = Math.cos(a), sa = Math.sin(a), ux = (m.dir[0] * ca - m.dir[1] * sa) / l, uy = (m.dir[0] * sa + m.dir[1] * ca) / l;
      stageShots.push({ kind: C.shot, big: skill, sc: 3, x: STX[i] + m.pt[0] * sc, y: GY + m.pt[1] * sc, vx: ux * 1100, vy: uy * 1100, t: 0, life: 0.5 });
    }
  } });
  stageEv.sort((a, b) => a.at - b.at);
}
document.getElementById('acts').addEventListener('click', (e) => { const b = e.target.closest('button'); if (b) pair.forEach((A, i) => { play(A, b.dataset.act); if (b.dataset.act === 'attack' || b.dataset.act === 'skill') stageFire(A, i, b.dataset.act === 'skill'); }); });
const toggle = (id, fn) => { const b = document.getElementById(id); b.addEventListener('click', () => { const on = b.getAttribute('aria-pressed') !== 'true'; b.setAttribute('aria-pressed', on); fn(on); }); };
toggle('bones', (on) => { showBones = on; });
toggle('slow', (on) => { slow = on; });
toggle('stance', (on) => { for (const A of pair) A.stance = on; });
function setClass(id) {
  stageCls = id; stageEv = []; stageShots = [];
  pair.forEach((A, i) => { pair[i] = makeActor(A.stance, A.view, id); });
  for (const b of document.querySelectorAll('#cls button')) b.setAttribute('aria-pressed', b.dataset.cls === id);
  if (typeof drawSheet === 'function') drawSheet();
}
const clsRow = document.getElementById('cls');
if (clsRow) clsRow.addEventListener('click', (e) => { const b = e.target.closest('button'); if (b) setClass(b.dataset.cls); });

// ---- the board: the game's own 7 x 8 battle board (720 px base width, 88 px cells), enemy on top, player below
const bd = document.getElementById('board'), bx = bd.getContext('2d');
const CELL = 88, BX0 = 52, BY0 = 28, SC = 1.3;
const cellX = (c) => BX0 + (c + 0.5) * CELL, feetY = (r) => BY0 + (r + 1) * CELL - 17;
// mixed line-up: melee in front (they meet at the centre line), Cung and Pháp two rows back, Kỵ charging from the far edge
const LINEUP = [ // side, class, column, start row, battle row, hp
  [0, 'ky', 0, 7, 4, 5], [0, 'khien', 2, 5, 4, 6], [0, 'kiem', 4, 5, 4, 5], [0, 'thuong', 6, 5, 4, 5], [0, 'cung', 2, 6, 6, 3], [0, 'phap', 4, 6, 6, 3],
  [1, 'thuong', 0, 2, 3, 3], [1, 'kiem', 2, 2, 3, 4], [1, 'khien', 4, 2, 3, 4], [1, 'ky', 6, 0, 3, 3], [1, 'phap', 2, 1, 1, 2], [1, 'cung', 4, 1, 1, 2],
];
let units = [], events = [], floats = [], shots = [], clockB = 0;
function boardReset() {
  units = []; events = []; floats = []; shots = []; clockB = 0;
  const at = (t, fn) => events.push({ t, fn });
  for (const [side, cls, col, r0, r1, hp] of LINEUP) {
    const u = { A: makeActor(true, side ? 'front' : 'back', cls), cls, side, hp, max: hp, shown: hp, khi: 0.15, x: cellX(col), y: feetY(r0), fx: cellX(col), fy: feetY(r0), tx: cellX(col), ty: feetY(r1), gone: 1e9, ranged: !!CLS[cls].shot, plan: hp, dieAt: 1e9, n: 0 };
    units.push(u);
  }
  for (const u of units) { u.duel = u.ranged ? null : units.find((v) => v.side !== u.side && !v.ranged && v.tx === u.tx); u.tgt = u.duel || units.find((v) => v.side !== u.side && !v.ranged); }
  // plan the fight: every unit attacks on its own beat; melee fights its column, then runs at a free archer or mage;
  // Cung shoots the nearest front-liner, Pháp the enemy back line
  units.forEach((u, i) => { u.next = u.ranged ? 2.0 + (i % 6) * 0.18 + u.side * 0.3 : 2.2 + (i % 6) * 0.27 + u.side * 0.13; });
  let end = 0;
  for (let guard = 0; guard < 200; guard++) {
    const u = units.filter((v) => v.next < 40).sort((a, b) => a.next - b.next)[0]; if (!u) break;
    const t = u.next; if (u.dieAt <= t) { u.next = 1e9; continue; }
    const foes = units.filter((v) => v.side !== u.side && v.plan > 0);
    const tgt = u.ranged ? foes.filter((v) => v.ranged === (u.cls === 'phap')).sort((a, b) => Math.abs(a.tx - u.tx) - Math.abs(b.tx - u.tx))[0] || foes[0] : (u.duel && u.duel.plan > 0 ? u.duel : null);
    if (!tgt && !u.ranged) {
      // a melee winner runs at the nearest enemy archer or mage not yet taken and fights it from the next cell
      const r = foes.filter((v) => v.ranged && !v.claimed).sort((a, b) => Math.abs(a.tx - u.tx) - Math.abs(b.tx - u.tx))[0];
      if (r) { r.claimed = true; u.duel = r; const nx = r.tx, ny = r.ty + (u.side ? -CELL : CELL); at(t, () => { u.fx = u.x; u.fy = u.y; u.tx = nx; u.ty = ny; u.t0 = clockB; u.tgt = r; play(u.A, 'walk', 0.95); }); u.next = t + 1.15; continue; }
    }
    if (!tgt) { u.next = 1e9; continue; }
    const C = CLS[u.cls], skill = u.n === 2, dmg = skill ? 2 : 1;
    let hitAt = t + C.hitT[skill ? 1 : 0], fly = 0;
    if (u.ranged) { fly = Math.hypot(tgt.tx - u.tx, tgt.ty - u.ty) / (C.shot === 'arrow' ? 900 : 650); hitAt = t + C.release[skill ? 1 : 0] + fly; }
    tgt.plan -= dmg; const dead = tgt.plan <= 0; if (dead) tgt.dieAt = hitAt;
    const shownDmg = skill ? 88 + u.n * 3 : 42 + ((u.n * 7 + units.indexOf(u) * 5) % 12);
    at(t, () => { u.tgt = tgt; play(u.A, skill ? 'skill' : 'attack'); u.khi = skill ? 0 : Math.min(1, u.khi + 0.42); });
    if (u.ranged) at(t + C.release[skill ? 1 : 0], () => fireShot(u, tgt, skill, fly));
    at(hitAt, () => { tgt.shown = Math.max(0, tgt.shown - dmg); tgt.khi = Math.min(1, tgt.khi + 0.1); play(tgt.A, dead ? 'fall' : 'hit'); if (dead) tgt.gone = clockB + 1.6; floats.push({ x: tgt.x, y: tgt.y - 98, t: 0, text: shownDmg + (skill ? '!' : ''), big: skill }); });
    u.n++; u.next = t + (skill ? 1.3 : u.ranged ? 1.15 : 0.9); end = Math.max(end, hitAt);
  }
  at(0.7, () => { for (const u of units) if (u.ty !== u.fy) { play(u.A, 'walk', 0.95); u.t0 = clockB; } });
  at(end + 0.8, () => { for (const u of units) if (u.shown > 0) play(u.A, 'cheer'); });
  at(end + 3.6, boardReset);
  events.sort((a, b) => a.t - b.t);
}
function fireShot(u, tgt, skill, fly) {
  const C = CLS[u.cls], q = Object.assign({}, u.A.cur, { dx: 0 }), M = solve(q, u.A.view), m = C.muzzle(M, q, u.A.view), f = u.flip ? -1 : 1;
  const x0 = (u.ox ?? u.x) + f * m.pt[0] * SC, y0 = (u.oy ?? u.y) + m.pt[1] * SC;
  for (const a of skill && C.shot === 'arrow' ? [-14, 0, 14] : [0]) shots.push({ kind: C.shot, big: skill, sc: C.shot === 'bolt' ? 2 : 1.4, x0, y0, x1: tgt.tx + a, y1: tgt.ty - 40 + Math.abs(a) * 0.4, t: 0, dur: fly, arc: C.shot === 'arrow' ? 0.12 : 0 });
}
function rr(c, x, y, w, h, r) { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath(); }
function boardTick(dt) {
  clockB += dt;
  while (events.length && events[0].t <= clockB) events.shift().fn();
  const W = bd.width, H = bd.height;
  bx.fillStyle = '#161a2e'; bx.fillRect(0, 0, W, H);
  rr(bx, BX0 - 10, BY0 - 10, 7 * CELL + 20, 8 * CELL + 20, 12); bx.fillStyle = '#e6d3ab'; bx.fill(); bx.strokeStyle = PAL.INK; bx.lineWidth = 4; bx.stroke();
  for (let r = 0; r < 8; r++) for (let q = 0; q < 7; q++) { rr(bx, BX0 + q * CELL + 3, BY0 + r * CELL + 3, CELL - 6, CELL - 6, 6); bx.fillStyle = r < 4 ? '#f0dcc0' : '#f3e6c8'; bx.fill(); }
  const my = BY0 + 4 * CELL; bx.fillStyle = PAL.INK; bx.fillRect(BX0 - 8, my - 1.5, 7 * CELL + 16, 3);
  for (const x of [BX0 - 8, BX0 + 7 * CELL + 8]) { bx.fillStyle = PAL.VERMILION; bx.strokeStyle = PAL.INK; bx.lineWidth = 2; bx.beginPath(); bx.arc(x, my, 6, 0, 7); bx.fill(); bx.stroke(); }
  for (const u of units) {
    if (u.t0 !== undefined) { const k = clamp((clockB - u.t0) / 0.95, 0, 1); u.x = lerp(u.fx, u.tx, k); u.y = lerp(u.fy, u.ty, k); }
    update(u.A, dt);
  }
  for (const u of units.slice().sort((a, b) => a.y - b.y)) {
    if (clockB > u.gone) continue;
    const C = CLS[u.cls], p = u.A.cur, T = u.tgt || u, side = (T.tx >= u.tx ? 1 : -1) * (C.aimB ? -1 : 1);
    const ddx = T.x - u.x, ddy = T.y - u.y, dl = Math.hypot(ddx, ddy) || 1;
    const push = p.dx > 0 ? p.dx * 4.6 : p.dx * 2, ox = u.x + ddx / dl * push, oy = u.y + ddy / dl * push, q = Object.assign({}, p, { dx: 0 });
    bx.globalAlpha = p.alpha; bx.beginPath(); bx.ellipse(u.x, u.y + 2, 30, 10, 0, 0, 7); bx.fillStyle = u.side ? 'rgba(210,70,46,0.22)' : 'rgba(79,127,214,0.22)'; bx.fill(); bx.strokeStyle = u.side ? '#d2462e' : '#4f7fd6'; bx.lineWidth = 3; bx.stroke(); bx.globalAlpha = 1;
    u.ox = ox; u.oy = oy; u.flip = side < 0;
    drawFigure(bx, q, solve(q, u.A.view), ox, oy, SC, { trail: u.A.trail, flip: u.flip, view: u.A.view, noShadow: true, cls: u.cls });
    if (u.shown > 0) {
      const bw = 56, x0 = u.x - bw / 2, by = u.y - 100;
      bx.fillStyle = PAL.INK; bx.fillRect(x0 - 2, by - 2, bw + 4, 15); bx.fillStyle = '#3a4369'; bx.fillRect(x0, by, bw, 11);
      bx.fillStyle = u.side ? '#e0533c' : '#4fbf86'; bx.fillRect(x0, by, bw * u.shown / u.max, 7); bx.fillStyle = '#58a6ff'; bx.fillRect(x0, by + 8, bw * u.khi, 3);
      bx.fillStyle = PAL.GOLD; bx.strokeStyle = PAL.INK; bx.lineWidth = 1.5; bx.beginPath(); bx.moveTo(u.x, by - 12); bx.lineTo(u.x + 5, by - 7); bx.lineTo(u.x, by - 2.5); bx.lineTo(u.x - 5, by - 7); bx.closePath(); bx.fill(); bx.stroke();
    }
  }
  for (const s of shots) {
    s.t += dt; const k = Math.min(1, s.t / s.dur), d = Math.hypot(s.x1 - s.x0, s.y1 - s.y0), lift = s.arc * d * 4;
    const x = lerp(s.x0, s.x1, k), y = lerp(s.y0, s.y1, k) - lift * k * (1 - k), vx = s.x1 - s.x0, vy = s.y1 - s.y0 - lift * (1 - 2 * k);
    if (k < 1) drawShot(bx, s, x, y, vx, vy);
    else if (s.kind === 'bolt') { const e = (s.t - s.dur) / 0.3; bx.globalAlpha = clamp(1 - e, 0, 1); bx.strokeStyle = s.big ? PAL.GOLD : PAL.ORB; bx.lineWidth = 4; bx.beginPath(); bx.arc(s.x1, s.y1, 10 + e * (s.big ? 40 : 24), 0, 7); bx.stroke(); bx.globalAlpha = 1; }
  }
  shots = shots.filter((s) => s.t < s.dur + 0.3);
  bx.textAlign = 'center'; bx.lineJoin = 'round';
  for (const f of floats) { f.t += dt; const k = f.t / 0.9; bx.globalAlpha = clamp(2.2 - 2.2 * k, 0, 1); bx.font = `800 ${f.big ? 34 : 26}px "Be Vietnam Pro", system-ui, sans-serif`; bx.lineWidth = 5; bx.strokeStyle = PAL.INK; bx.fillStyle = f.big ? PAL.GOLD : PAL.CREAM; const y = f.y - 26 * (1 - (1 - k) * (1 - k)); bx.strokeText(f.text, f.x, y); bx.fillText(f.text, f.x, y); }
  bx.globalAlpha = 1; floats = floats.filter((f) => f.t < 0.9);
}
boardReset();
document.getElementById('restart').addEventListener('click', boardReset);
requestAnimationFrame(frame);

// ---- the loose pieces of the selected class, laid out with their joints marked
const SHEET_TOP = [['head', 'front', 'Đầu, mặt trước', 92, 150, 28], ['head', 'back', 'Đầu, mặt sau', 262, 150, 28], ['torso', 'front', 'Thân trước', 440, 176, 34], ['torso', 'back', 'Thân sau', 612, 176, 34]];
const SHEET_ARM = [['uaF', 0, 0, 360, 250, 84], ['laF', 0, 0, 480, 250, 78], ['hF', 0, 0, 610, 270, 50]];
const SHEET_LEG = [['thF', 0, 0, 80, 392, 100], ['shF', 0, 0, 200, 392, 100], ['ftF', 0, 0, 330, 440, 44]];
const SHEETS = { // [id, view, label, x, y, label offset, scale, label dx]
  kiem: [['skirt', 0, 0, 92, 262, 56], ['pauldron', 0, 0, 240, 274, 50], ...SHEET_ARM, ...SHEET_LEG, ['sword', 0, 0, 450, 436, 50, 5, 60]],
  khien: [['skirt', 0, 0, 92, 262, 56], ['pauldron', 0, 0, 240, 274, 50], ...SHEET_ARM, ...SHEET_LEG, ['sword', 0, 0, 385, 436, 50, 4, 46], ['shield', 'front', 'Khiên', 572, 418, 66, 3.3], ['shield', 'back', 'Mặt sau', 670, 418, 66, 2.4]],
  thuong: [['skirt', 0, 0, 92, 262, 56], ...SHEET_ARM, ...SHEET_LEG, ['spear', 0, 0, 470, 436, 50, 3.6, 70]],
  cung: [['skirt', 0, 0, 92, 262, 56], ['quiver', 0, 0, 240, 316, 34, 3.4], ...SHEET_ARM, ...SHEET_LEG, ['bow', 0, 0, 520, 420, 88, 3.6]],
  phap: [['skirt', 0, 0, 92, 236, 132, 4.2], ...SHEET_ARM.map((r) => r.slice()), ['thF', 0, 0, 200, 392, 100], ['shF', 0, 0, 290, 392, 100], ['staff', 0, 0, 470, 436, 50, 4, 30]],
  ky: [['skirt', 0, 0, 92, 262, 56], ['pauldron', 0, 0, 240, 274, 50], ...SHEET_ARM, ['lance', 0, 0, 92, 430, 60, 3, 90], ['horse', 'back', 'Ngựa, mặt sau', 400, 482, 26, 2.6], ['horse', 'front', 'Ngựa, mặt trước', 600, 482, 26, 2.6]],
};
const SHEET_NOTE = {
  kiem: 'Chỉ đầu và thân phải vẽ hai mặt. Tay chân, kiếm, giáp dùng chung.',
  khien: 'Khiên có hai mặt: mặt sơn khi nhìn từ trước, mặt gỗ khi nhìn từ lưng.',
  thuong: 'Hai tay cùng cầm cán: tay sau tự tìm tới cán thương.',
  cung: 'Cung vẽ theo hai bàn tay: dây cung đi theo tay kéo.',
  phap: 'Áo bào dài thay váy giáp, che gần hết chân.',
  ky: 'Ngựa là bộ vẽ riêng, có mặt sau và mặt trước, chân co khi phi.',
};
let drawSheet = null;
(function sheet() {
  const cv = document.getElementById('sheet'), c = cv.getContext('2d');
  const joint = () => { c.fillStyle = '#fff'; c.beginPath(); c.arc(0, 0, 1.25, 0, 7); c.fill(); c.fillStyle = PAL.VERMILION; c.beginPath(); c.arc(0, 0, 0.85, 0, 7); c.fill(); };
  drawSheet = () => {
    const C = CLS[stageCls], id8 = (s) => (k) => k, t = id8();
    c.clearRect(0, 0, cv.width, cv.height); c.lineJoin = 'round';
    const top = stageCls === 'ky' ? SHEET_TOP.map((r, i) => i < 2 ? [r[0], r[1], r[2], r[3], 176, 24, 3.6] : r) : SHEET_TOP;
    for (const [id, view, label, x, y, below, scl, ldx] of top.concat(SHEETS[stageCls])) {
      const sc = scl || 5, v = view || 'front';
      c.save(); c.translate(x, y); c.scale(sc, sc);
      if (id === 'horse') {
        const p = C.R.idle[v], M = solve(p, v); c.translate(0, 0);
        for (const set of zOrder(C, v)) for (const q of set) if (q.id.startsWith('h_')) { c.save(); q.draw(c, t, Object.assign({}, p, { dx: 0 }), v, { M }); c.restore(); }
      } else if (id === 'bow') {
        // a stand-alone bow: grip at the joint, the string pulled half way
        const M = { hB: [1, 0, 0, 1, 0, -1.5], hF: [1, 0, 0, 1, 9, -1.5] }; bowDraw(c, t, Object.assign({}, BASE, { draw: 0.5, nock: 1 }), v, { M }); joint();
      } else {
        const q = C.pieces.find((k) => k.id === id), K = { s: 1, view: v, heel: 0, p: null, M: null };
        if (q.draw) q.draw(c, t, null, v, K); else { c.beginPath(); q.path(c, K); c.strokeStyle = PAL.INK; c.lineWidth = 2.2; c.stroke(); c.fillStyle = q.col; c.fill(); if (q.detail) q.detail(c, t, null, v, K); }
        joint();
      }
      c.restore();
      const q = C.pieces.find((k) => k.id === id);
      c.fillStyle = PAL.INK; c.font = '800 21px "Be Vietnam Pro", system-ui, sans-serif'; c.textAlign = 'center';
      c.fillText(label || (q && q.name) || '', x + (ldx || (id === 'ftF' ? 4 : 0)), y + below);
    }
    c.font = '600 20px "Be Vietnam Pro", system-ui, sans-serif'; c.textAlign = 'left'; c.fillStyle = PAL.INK;
    c.fillText(SHEET_NOTE[stageCls], 24, 546);
  };
  drawSheet(); if (document.fonts && document.fonts.ready) document.fonts.ready.then(drawSheet);
  setInterval(drawSheet, 120);
})();
