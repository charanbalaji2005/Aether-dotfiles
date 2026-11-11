.pragma library
// Minimal assertion helpers for tst_*.qml. Each check prints one PASS/FAIL
// line; harness.py fails the file on any FAIL, any QML error, or a timeout.
var failures = 0;
function ok(cond, name) {
    if (cond) console.log("PASS " + name);
    else { failures++; console.log("FAIL " + name); }
}
function near(a, b, tol, name) {
    ok(Math.abs(a - b) <= tol, name + " (got " + a + ", want " + b + " ±" + tol + ")");
}
function colorNear(c, r, g, b, tol, name) {
    ok(Math.abs(c.r * 255 - r) <= tol && Math.abs(c.g * 255 - g) <= tol && Math.abs(c.b * 255 - b) <= tol,
       name + " (got " + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + ")");
}
