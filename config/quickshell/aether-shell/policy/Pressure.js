.pragma library
// GPU / VRAM pressure policy with hysteresis.
//
// Input: one sample per telemetry tick { usage: 0-1|null, vramUsed, vramTotal }
// for the GPU that draws the desktop. Output: whether the shell should step
// visual quality down, and why.
//
// Pressure starts only after `enterTicks` consecutive samples above the
// threshold and ends only after `exitTicks` consecutive samples below
// threshold − margin. A single spike (a game loading a level) never flips
// quality, and quality never oscillates around the threshold. Unknown
// values (null) count as "no pressure": a GPU without telemetry is never
// treated as overloaded.

function create(opts) {
    return {
        vramThreshold: opts && opts.vramThreshold !== undefined ? opts.vramThreshold : 0.88,
        gpuThreshold: opts && opts.gpuThreshold !== undefined ? opts.gpuThreshold : 0.92,
        margin: 0.08,
        enterTicks: 3,
        exitTicks: 10,
        above: 0,
        below: 0,
        active: false,
        reason: ""
    };
}

function step(state, sample) {
    var s = Object.assign({}, state);
    var vram = (sample && sample.vramTotal > 0 && sample.vramUsed >= 0) ? sample.vramUsed / sample.vramTotal : null;
    var gpu = (sample && typeof sample.usage === "number") ? sample.usage : null;
    var hot = (vram !== null && vram >= s.vramThreshold) || (gpu !== null && gpu >= s.gpuThreshold);
    var cool = (vram === null || vram < s.vramThreshold - s.margin) && (gpu === null || gpu < s.gpuThreshold - s.margin);
    if (hot) { s.above += 1; s.below = 0; }
    else if (cool) { s.below += 1; s.above = 0; }
    else { s.above = 0; }            // in the hysteresis band: hold the current state
    if (!s.active && s.above >= s.enterTicks) {
        s.active = true;
        s.reason = vram !== null && vram >= s.vramThreshold
            ? "GPU memory " + Math.round(vram * 100) + "% full"
            : "GPU " + Math.round(gpu * 100) + "% busy";
    } else if (s.active && s.below >= s.exitTicks) {
        s.active = false;
        s.reason = "";
    }
    return s;
}
