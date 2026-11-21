/*
 * Terminal Tiler: a KWin script that tiles terminal windows only.
 *
 * Rules
 *  - Only windows whose class / app id is in the terminal list are touched.
 *    Firefox and every other app are never moved or resized.
 *  - Terminals are grouped per screen + virtual desktop.
 *  - A group with ONE terminal is left alone: it keeps the size it opened with.
 *  - A group with TWO OR MORE terminals fills the whole screen (work area).
 *  - When a group drops back to one terminal, that terminal gets back the
 *    exact geometry it had before it was tiled.
 *  - Minimized terminals don't count. Maximized and fullscreen terminals keep
 *    their slot but are left as they are until you restore them.
 *  - A terminal you snap yourself (Meta+arrow keys, dragging it to a screen
 *    edge, or KWin's tile editor) is yours: it is left exactly where you put
 *    it. Un-snap it and it joins the automatic tiling again.
 *  - Drag a tiled terminal onto another one to swap them. Drag the edge
 *    between the left and right column to change the split.
 *  - Panels set to "Windows go below" (like a floating dock) don't reserve
 *    space, so tiles stop short of them.
 */
"use strict";

var DEFAULT_CLASSES =
    "com.mitchellh.ghostty,ghostty,org.kde.konsole,konsole,org.gnome.terminal," +
    "gnome-terminal-server,gnome-terminal,org.gnome.console,kgx,org.gnome.ptyxis,ptyxis," +
    "kitty,alacritty,org.wezfurlong.wezterm,wezterm,foot,footclient,xterm,uxterm,urxvt," +
    "st,st-256color,terminator,tilix,com.gexperts.tilix,xfce4-terminal,lxterminal," +
    "qterminal,terminology,cool-retro-term,dev.warp.warp,warp,rio,contour";

var LAYOUT_TILE = 0;
var LAYOUT_COLUMNS = 1;
var LAYOUT_ROWS = 2;
var LAYOUT_GRID = 3;
var LAYOUT_COUNT = 4;
var LAYOUT_NAMES = ["Master and stack", "Columns", "Rows", "Grid"];
var MIN_RATIO = 0.15;
var MAX_RATIO = 0.85;
var RATIO_STEP = 0.05;

var cfg = {
    classes: {},
    gap: 8,
    ratio: 0.5,
    layout: LAYOUT_GRID,
    newAsMaster: false,
    avoidPanels: true
};

/* ------------------------------------------------------------------ state */

var entries = {};       // window id -> entry (terminals only)
var order = [];         // window ids, tiling order (first = master)
var hooked = {};        // window id -> true once signals are connected
var ratios = {};        // group key -> master ratio
var naturalSizes = {};  // window class -> size it last opened with
var enabled = true;
var busy = false;
var starting = true;

function log(msg) {
    print("TerminalTiler: " + msg);
}

/* ---------------------------------------------------------------- helpers */

function toNumber(v, fallback) {
    var n = Number(v);
    return isFinite(n) ? n : fallback;
}

function toBool(v, fallback) {
    if (v === true || v === false) return v;
    if (typeof v === "string") return v.toLowerCase() === "true";
    if (typeof v === "number") return v !== 0;
    return fallback;
}

function clamp(v, lo, hi) {
    return Math.min(hi, Math.max(lo, v));
}

function clampRatio(r) {
    return clamp(r, MIN_RATIO, MAX_RATIO);
}

function loadConfig() {
    var raw = String(readConfig("TerminalClasses", DEFAULT_CLASSES));
    var list = raw.split(/[,\s]+/);
    cfg.classes = {};
    for (var i = 0; i < list.length; i++) {
        var c = list[i].trim().toLowerCase();
        if (c.length > 0) cfg.classes[c] = true;
    }
    cfg.gap = Math.round(clamp(toNumber(readConfig("Gap", 8), 8), 0, 64));
    cfg.ratio = clampRatio(toNumber(readConfig("MasterRatio", 50), 50) / 100);
    cfg.layout = Math.round(clamp(toNumber(readConfig("Layout", LAYOUT_GRID), LAYOUT_GRID), 0, LAYOUT_COUNT - 1));
    cfg.newAsMaster = toBool(readConfig("NewAsMaster", false), false);
    cfg.avoidPanels = toBool(readConfig("AvoidFloatingPanels", true), true);
}

function idOf(w) {
    return String(w.internalId);
}

function classKey(w) {
    return String(w.resourceClass || w.desktopFileName || w.resourceName || "").toLowerCase();
}

function isTerminal(w) {
    if (!w || w.deleted || !w.normalWindow || w.transient) return false;
    var names = [w.resourceClass, w.resourceName, w.desktopFileName];
    for (var i = 0; i < names.length; i++) {
        if (names[i] && cfg.classes[String(names[i]).toLowerCase()] === true) return true;
    }
    return false;
}

function makeRect(x, y, width, height) {
    return {
        x: Math.round(x),
        y: Math.round(y),
        width: Math.max(1, Math.round(width)),
        height: Math.max(1, Math.round(height))
    };
}

function copyRect(g) {
    return { x: g.x, y: g.y, width: g.width, height: g.height };
}

function sameRect(a, b) {
    return Math.abs(a.x - b.x) < 1 && Math.abs(a.y - b.y) < 1 &&
           Math.abs(a.width - b.width) < 1 && Math.abs(a.height - b.height) < 1;
}

function containsPoint(r, p) {
    return p.x >= r.x && p.x < r.x + r.width && p.y >= r.y && p.y < r.y + r.height;
}

function maxOrFull(w) {
    return w.fullScreen || w.maximizeMode !== 0;
}

function onCurrentActivity(w) {
    var acts = w.activities;
    if (!acts || acts.length === 0) return true;
    for (var i = 0; i < acts.length; i++) {
        if (acts[i] === workspace.currentActivity) return true;
    }
    return false;
}

function visibleDesktop(output) {
    if (output && typeof workspace.currentDesktopForScreen === "function") {
        try {
            var d = workspace.currentDesktopForScreen(output);
            if (d) return d;
        } catch (e) {
            // fall through
        }
    }
    return workspace.currentDesktop;
}

function desktopOf(w) {
    if (w.desktops && w.desktops.length === 1) return w.desktops[0];
    return visibleDesktop(w.output);
}

function groupKey(w) {
    return w.output.name + "\u0001" + w.desktops[0].id;
}

function workArea(output, desktop) {
    return workspace.clientArea(KWin.MaximizeArea, output, desktop);
}

// The area tiles may use: the work area, minus panels that sit inside it
// without reserving space (Plasma's "Windows go below" / floating docks).
function tilingArea(output, desktop) {
    var a = workArea(output, desktop);
    var left = a.x, top = a.y, right = a.x + a.width, bottom = a.y + a.height;
    if (cfg.avoidPanels) {
        var list = workspace.stackingOrder;
        for (var i = 0; i < list.length; i++) {
            var d = list[i];
            if (!d.dock || d.deleted || d.hidden || d.minimized || !d.output || d.output.name !== output.name) continue;
            var g = d.frameGeometry;
            var ox = Math.min(g.x + g.width, right) - Math.max(g.x, left);
            var oy = Math.min(g.y + g.height, bottom) - Math.max(g.y, top);
            if (ox <= 0 || oy <= 0) continue;
            if (g.width >= g.height) {
                // Horizontal panel. Panels that reserve space only poke in by
                // their floating margin; ignore those.
                if (oy * 2 <= g.height) continue;
                if (g.y + g.height / 2 > top + (bottom - top) / 2) bottom = Math.min(bottom, g.y);
                else top = Math.max(top, g.y + g.height);
            } else {
                if (ox * 2 <= g.width) continue;
                if (g.x + g.width / 2 > left + (right - left) / 2) right = Math.min(right, g.x);
                else left = Math.max(left, g.x + g.width);
            }
        }
    }
    if (right - left < 200 || bottom - top < 200) {
        // Something odd: ignore panels.
        left = a.x; top = a.y; right = a.x + a.width; bottom = a.y + a.height;
    }

    // Terminals the user snapped to one side (e.g. top-left + bottom-left)
    // own that side: automatic tiles use what is left of the screen.
    var box = snappedBox(output, desktop);
    if (box) {
        var W = a.width, H = a.height;
        var fullHeight = box.top <= a.y + H * 0.1 && box.bottom >= a.y + H * 0.9;
        var fullWidth = box.left <= a.x + W * 0.1 && box.right >= a.x + W * 0.9;
        var atLeft = box.left <= a.x + W * 0.1, atRight = box.right >= a.x + W * 0.9;
        var atTop = box.top <= a.y + H * 0.1, atBottom = box.bottom >= a.y + H * 0.9;
        var nl = left, nt = top, nr = right, nb = bottom;
        if (fullHeight && atLeft && !atRight) nl = Math.max(left, box.right);
        else if (fullHeight && atRight && !atLeft) nr = Math.min(right, box.left);
        else if (fullWidth && atTop && !atBottom) nt = Math.max(top, box.bottom);
        else if (fullWidth && atBottom && !atTop) nb = Math.min(bottom, box.top);
        if (nr - nl >= W * 0.2 && nb - nt >= H * 0.2) {
            left = nl; top = nt; right = nr; bottom = nb;
        }
    }
    return { x: left, y: top, width: right - left, height: bottom - top };
}

// Bounding box of the visible terminals the user snapped on this screen/desktop.
function snappedBox(output, desktop) {
    var box = null;
    for (var id in entries) {
        if (!entries.hasOwnProperty(id)) continue;
        var e = entries[id];
        var w = e.win;
        if (stateOf(e) !== "user" || w.output.name !== output.name) continue;
        if (!w.onAllDesktops && !(w.desktops.length > 0 && desktop && w.desktops.some(function (d) { return d.id === desktop.id; }))) continue;
        var g = w.frameGeometry;
        if (!box) {
            box = { left: g.x, top: g.y, right: g.x + g.width, bottom: g.y + g.height };
        } else {
            box.left = Math.min(box.left, g.x);
            box.top = Math.min(box.top, g.y);
            box.right = Math.max(box.right, g.x + g.width);
            box.bottom = Math.max(box.bottom, g.y + g.height);
        }
    }
    return box;
}

/*
 * "tile"   -> takes part in tiling on a visible desktop
 * "user"   -> snapped by the user (quick tile / KWin tile): never touched
 * "float"  -> visible but must not be tiled (user floated it, tiling off,
 *             on all desktops, not resizable)
 * "hidden" -> minimized, other desktop or other activity: leave it alone
 */
function stateOf(e) {
    var w = e.win;
    if (w.deleted || !w.output) return "hidden";
    if (w.minimized || !onCurrentActivity(w)) return "hidden";
    if (w.tile) return "user";
    if (!enabled || e.floating || w.onAllDesktops || !w.desktops || w.desktops.length !== 1 ||
        !w.resizeable || !w.moveable) {
        return "float";
    }
    if (w.desktops[0].id !== visibleDesktop(w.output).id) return "hidden";
    return "tile";
}

/* ----------------------------------------------------------------- layout */

// Split [start, start+length) into `count` cells separated by `gap`,
// with integer edges and no rounding holes.
function split(start, length, count, gap) {
    var usable = length - gap * (count - 1);
    var cells = [];
    for (var i = 0; i < count; i++) {
        var a = start + Math.round(i * usable / count) + i * gap;
        var b = start + Math.round((i + 1) * usable / count) + i * gap;
        cells.push([a, b - a]);
    }
    return cells;
}

function computeLayout(n, area, ratio, layout) {
    var g = cfg.gap;
    var X = Math.round(area.x) + g;
    var Y = Math.round(area.y) + g;
    var W = Math.round(area.width) - 2 * g;
    var H = Math.round(area.height) - 2 * g;
    var rects = [];
    var cells, i;

    if (layout === LAYOUT_COLUMNS) {
        cells = split(X, W, n, g);
        for (i = 0; i < n; i++) rects.push(makeRect(cells[i][0], Y, cells[i][1], H));
        return rects;
    }
    if (layout === LAYOUT_ROWS) {
        cells = split(Y, H, n, g);
        for (i = 0; i < n; i++) rects.push(makeRect(X, cells[i][0], W, cells[i][1]));
        return rects;
    }

    if (layout === LAYOUT_GRID) {
        // Columns of windows. The first window always has the left column to
        // itself or shares it last, so opening one more terminal moves as few
        // others as possible: 2 = side by side, 3 = 1 left + 2 right,
        // 4 = 2x2, 5 = 1 + 2 + 2, 6 = 3x2 ...
        var cols = gridColumns(n);
        var colCells;
        if (cols === 2) {
            var leftW = Math.round((W - g) * ratio);
            colCells = [[X, leftW], [X + leftW + g, W - g - leftW]];
        } else {
            colCells = split(X, W, cols, g);
        }
        var base = Math.floor(n / cols);
        var extra = n % cols;
        var perCol = [];
        for (var c = 0; c < cols; c++) {
            var count = base + (c >= cols - extra ? 1 : 0);
            perCol.push(split(Y, H, count, g).map(function (cell) {
                return makeRect(colCells[c][0], cell[0], colCells[c][1], cell[1]);
            }));
        }
        rects.push(perCol[0][0]);
        for (c = 1; c < cols; c++) rects = rects.concat(perCol[c]);
        rects = rects.concat(perCol[0].slice(1));
        return rects;
    }

    // Master and stack
    var masterW = Math.round((W - g) * ratio);
    var stackX = X + masterW + g;
    var stackW = W - g - masterW;
    rects.push(makeRect(X, Y, masterW, H));
    cells = split(Y, H, n - 1, g);
    for (i = 0; i < n - 1; i++) rects.push(makeRect(stackX, cells[i][0], stackW, cells[i][1]));
    return rects;
}

function gridColumns(n) {
    return Math.max(1, Math.ceil(Math.sqrt(n)));
}

// Whether the left/right split ratio means anything for n windows.
function usesRatio(n) {
    return cfg.layout === LAYOUT_TILE || (cfg.layout === LAYOUT_GRID && gridColumns(n) === 2);
}

function ratioFor(key) {
    return ratios.hasOwnProperty(key) ? ratios[key] : cfg.ratio;
}

function slotsFor(key, grp) {
    return computeLayout(grp.members.length, tilingArea(grp.output, grp.desktop), ratioFor(key), cfg.layout);
}

function collectGroups() {
    var groups = {};
    var keys = [];
    var floats = [];
    for (var i = 0; i < order.length; i++) {
        var e = entries[order[i]];
        if (!e) continue;
        var s = stateOf(e);
        if (s === "tile") {
            var k = groupKey(e.win);
            if (!groups.hasOwnProperty(k)) {
                groups[k] = { output: e.win.output, desktop: e.win.desktops[0], members: [] };
                keys.push(k);
            }
            groups[k].members.push(e);
        } else if (s === "float") {
            floats.push(e);
        }
    }
    return { groups: groups, keys: keys, floats: floats };
}

function applyGeometry(w, r) {
    if (!sameRect(w.frameGeometry, r)) w.frameGeometry = r;
}

function fallbackGeometry(w, area) {
    var size = naturalSizes[classKey(w)];
    var width = size ? size.width : Math.round(area.width * 0.7);
    var height = size ? size.height : Math.round(area.height * 0.85);
    return makeRect(area.x + (area.width - width) / 2, area.y + (area.height - height) / 2, width, height);
}

function fitInto(g, area) {
    var width = Math.min(g.width, area.width);
    var height = Math.min(g.height, area.height);
    var x = g.x;
    var y = g.y;
    if (!containsPoint(area, { x: g.x + g.width / 2, y: g.y + g.height / 2 })) {
        // Saved geometry belongs to another screen: center it on this one.
        x = area.x + (area.width - width) / 2;
        y = area.y + (area.height - height) / 2;
    }
    x = clamp(x, area.x, area.x + area.width - width);
    y = clamp(y, area.y, area.y + area.height - height);
    return makeRect(x, y, width, height);
}

// Give a terminal back the geometry it had before it was tiled.
function restoreFloating(e) {
    var w = e.win;
    if (maxOrFull(w)) return; // keep `tiled`; restored once un-maximized
    e.tiled = false;
    var area = workArea(w.output, desktopOf(w));
    var g = e.floatGeo ? e.floatGeo : fallbackGeometry(w, area);
    if (e.restoreHere) {
        // Just dragged somewhere by the user: natural size, but where it was dropped.
        g = makeRect(w.frameGeometry.x, w.frameGeometry.y, g.width, g.height);
        e.centerOnRestore = false;
    } else if (e.centerOnRestore) {
        g = makeRect(area.x + (area.width - g.width) / 2, area.y + (area.height - g.height) / 2, g.width, g.height);
        e.centerOnRestore = false;
    }
    e.floatGeo = null;
    applyGeometry(w, fitInto(g, area));
}

function doRetile() {
    var data = collectGroups();
    var i;

    for (i = 0; i < data.floats.length; i++) {
        if (data.floats[i].tiled) restoreFloating(data.floats[i]);
    }

    for (var k = 0; k < data.keys.length; k++) {
        var key = data.keys[k];
        var grp = data.groups[key];

        if (grp.members.length === 1) {
            var solo = grp.members[0];
            if (solo.tiled) restoreFloating(solo);
            continue;
        }

        var rects = slotsFor(key, grp);
        for (i = 0; i < grp.members.length; i++) {
            var e = grp.members[i];
            var w = e.win;
            if (maxOrFull(w)) continue; // keeps its slot, left as is
            if (!e.tiled) {
                // Remember the geometry to go back to when it is alone again.
                // On script start-up a window already sitting exactly in its
                // slot was tiled by a previous run: its own size is unknown.
                e.floatGeo = (starting && sameRect(w.frameGeometry, rects[i])) ? null : copyRect(w.frameGeometry);
                e.tiled = true;
            }
            applyGeometry(w, rects[i]);
        }
    }
}

function anyInteractive() {
    for (var id in entries) {
        if (entries.hasOwnProperty(id) && entries[id].interactive) return true;
    }
    return false;
}

function retile() {
    if (busy || anyInteractive()) return;
    busy = true;
    try {
        doRetile();
    } catch (err) {
        log("error while tiling: " + err);
    } finally {
        busy = false;
    }
}

/* ---------------------------------------------------------------- windows */

// A new terminal joined a group: if that makes 2+ terminals, un-maximize the
// group (the new window included, some apps reopen maximized) so they split.
function unmaximizeGroup(e) {
    if (stateOf(e) !== "tile") return;
    var key = groupKey(e.win);
    var group = [];
    for (var id in entries) {
        if (!entries.hasOwnProperty(id)) continue;
        var o = entries[id];
        if (stateOf(o) === "tile" && groupKey(o.win) === key) group.push(o);
    }
    if (group.length < 2) return;
    for (var i = 0; i < group.length; i++) {
        var w = group[i].win;
        if (w.maximizeMode !== 0 && !w.fullScreen) {
            // A window that opened maximized has no real position of its
            // own; center it if it ever goes back to floating.
            if (group[i] === e) e.centerOnRestore = true;
            w.setMaximize(false, false);
        }
    }
}

function track(w, isNew) {
    var id = idOf(w);
    if (entries.hasOwnProperty(id)) return entries[id];
    var e = {
        win: w,
        id: id,
        floating: false,
        tiled: false,
        floatGeo: null,
        centerOnRestore: false,
        restoreHere: false,
        interactive: false,
        drag: null
    };
    entries[id] = e;
    if (isNew && cfg.newAsMaster) order.unshift(id);
    else order.push(id);

    if (isNew) {
        if (!maxOrFull(w)) {
            naturalSizes[classKey(w)] = { width: w.frameGeometry.width, height: w.frameGeometry.height };
        }
        // Opening another terminal next to a maximized one splits them.
        busy = true;
        try { unmaximizeGroup(e); } finally { busy = false; }
    }
    return e;
}

function untrack(id, restore) {
    var e = entries[id];
    if (!e) return;
    if (restore && e.tiled && !e.win.deleted) {
        busy = true;
        try { restoreFloating(e); } finally { busy = false; }
    }
    delete entries[id];
    var idx = order.indexOf(id);
    if (idx !== -1) order.splice(idx, 1);
}

function reevaluate(w) {
    var id = idOf(w);
    var term = isTerminal(w);
    if (term && !entries.hasOwnProperty(id)) {
        track(w, false);
        retile();
    } else if (!term && entries.hasOwnProperty(id)) {
        untrack(id, true);
        retile();
    }
}

function onDragStart(id) {
    var e = entries[id];
    if (!e) return;
    var w = e.win;
    e.interactive = true;
    e.drag = {
        resize: !!w.resize,
        wasMaxOrFull: maxOrFull(w),
        start: copyRect(w.frameGeometry),
        key: stateOf(e) === "tile" ? groupKey(w) : null
    };
}

function adjustRatioFromResize(e, key, grp) {
    var n = grp.members.length;
    if (!usesRatio(n)) return;
    var idx = grp.members.indexOf(e);
    if (idx === -1) return;
    var area = tilingArea(grp.output, grp.desktop);
    var g = cfg.gap;
    var X = Math.round(area.x) + g;
    var denom = Math.round(area.width) - 3 * g;
    if (denom <= 0) return;
    var slot = slotsFor(key, grp)[idx];
    var geo = e.win.frameGeometry;
    // Left column: its right edge is the split. Right column: its left edge.
    var leftW = slot.x === X ? (geo.x + geo.width) - X : (geo.x - g) - X;
    ratios[key] = clampRatio(leftW / denom);
}

function reorderByDrop(e, key, grp, sameGroup) {
    var rects = slotsFor(key, grp);
    var cursor = workspace.cursorPos;
    var idx = -1;
    for (var i = 0; i < rects.length; i++) {
        if (containsPoint(rects[i], cursor)) { idx = i; break; }
    }
    if (idx === -1) return;
    var target = grp.members[idx];
    if (target === e) return;
    var a = order.indexOf(e.id);
    var b = order.indexOf(target.id);
    if (a === -1 || b === -1) return;
    if (sameGroup) {
        order[a] = target.id;
        order[b] = e.id;
    } else {
        order.splice(a, 1);
        order.splice(order.indexOf(target.id), 0, e.id);
    }
}

function onDragEnd(id) {
    var e = entries[id];
    if (!e) return;
    var d = e.drag;
    e.interactive = false;
    e.drag = null;
    try {
        if (d && stateOf(e) === "tile") {
            var w = e.win;
            var key = groupKey(w);
            var grp = collectGroups().groups[key];
            if (grp && grp.members.length >= 2) {
                var g = w.frameGeometry;
                // Dragging a maximized window un-maximizes it: that is a move.
                var resized = !d.wasMaxOrFull && (d.resize ||
                              Math.abs(g.width - d.start.width) > 2 ||
                              Math.abs(g.height - d.start.height) > 2);
                if (resized) {
                    if (e.tiled && key === d.key) adjustRatioFromResize(e, key, grp);
                } else {
                    reorderByDrop(e, key, grp, key === d.key);
                }
            }
        }
    } catch (err) {
        log("error after move/resize: " + err);
    }
    // If it ends up alone, give it its normal size where it was dropped.
    e.restoreHere = true;
    retile();
    e.restoreHere = false;
}

function hook(w) {
    if (!w) return;
    var id = idOf(w);
    if (hooked[id]) return;
    if (w.dock) {
        // Panels: their size/visibility changes the space tiles may use.
        hooked[id] = true;
        var panelChanged = function () { if (cfg.avoidPanels) retile(); };
        w.frameGeometryChanged.connect(panelChanged);
        w.hiddenChanged.connect(panelChanged);
        w.outputChanged.connect(panelChanged);
        return;
    }
    if (!w.normalWindow) return;
    hooked[id] = true;

    var reclass = function () { reevaluate(w); };
    w.windowClassChanged.connect(reclass);
    w.desktopFileNameChanged.connect(reclass);

    var re = function () { if (entries.hasOwnProperty(id)) retile(); };
    w.minimizedChanged.connect(re);
    w.fullScreenChanged.connect(re);
    w.maximizedChanged.connect(re);
    w.desktopsChanged.connect(re);
    w.activitiesChanged.connect(re);
    w.outputChanged.connect(re);
    // Snapping / un-snapping hands the window to the user / back to us.
    w.tileChanged.connect(re);
    w.quickTileModeChanged.connect(re);
    w.interactiveMoveResizeStarted.connect(function () { onDragStart(id); });
    w.interactiveMoveResizeFinished.connect(function () { onDragEnd(id); });
}

function onWindowAdded(w) {
    hook(w);
    if (w.dock) {
        if (cfg.avoidPanels) retile();
        return;
    }
    if (!isTerminal(w)) return;
    track(w, true);
    retile();
}

function onWindowRemoved(w) {
    var id = idOf(w);
    delete hooked[id];
    if (w.dock) {
        if (cfg.avoidPanels) retile();
        return;
    }
    if (!entries.hasOwnProperty(id)) return;
    untrack(id, false);
    retile();
}

function onConfigChanged() {
    loadConfig();
    ratios = {};
    var list = workspace.windowList();
    for (var i = 0; i < list.length; i++) {
        var w = list[i];
        hook(w);
        var id = idOf(w);
        var term = isTerminal(w);
        if (term && !entries.hasOwnProperty(id)) track(w, false);
        else if (!term && entries.hasOwnProperty(id)) untrack(id, true);
    }
    retile();
}

/* -------------------------------------------------------------- shortcuts */

function activeEntry() {
    var w = workspace.activeWindow;
    if (!w) return null;
    var id = idOf(w);
    return entries.hasOwnProperty(id) ? entries[id] : null;
}

// The tiled group the active terminal belongs to, if it has 2+ members.
function activeGroup() {
    var e = activeEntry();
    if (!e || stateOf(e) !== "tile") return null;
    var key = groupKey(e.win);
    var grp = collectGroups().groups[key];
    if (!grp || grp.members.length < 2) return null;
    return { entry: e, key: key, grp: grp, index: grp.members.indexOf(e) };
}

function focusStep(step) {
    var a = activeGroup();
    if (!a) return;
    var n = a.grp.members.length;
    workspace.activeWindow = a.grp.members[(a.index + step + n) % n].win;
}

function swapOrder(e1, e2) {
    var a = order.indexOf(e1.id);
    var b = order.indexOf(e2.id);
    if (a === -1 || b === -1) return;
    order[a] = e2.id;
    order[b] = e1.id;
}

function moveStep(step) {
    var a = activeGroup();
    if (!a) return;
    var n = a.grp.members.length;
    swapOrder(a.entry, a.grp.members[(a.index + step + n) % n]);
    retile();
}

function swapWithMaster() {
    var a = activeGroup();
    if (!a) return;
    var other = a.index === 0 ? a.grp.members[1] : a.grp.members[0];
    swapOrder(a.entry, other);
    retile();
}

function changeRatio(delta) {
    var a = activeGroup();
    if (!a) return;
    ratios[a.key] = clampRatio(ratioFor(a.key) + delta);
    retile();
}

function toggleFloat() {
    var e = activeEntry();
    if (!e) return;
    e.floating = !e.floating;
    retile();
}

function toggleTiling() {
    enabled = !enabled;
    log(enabled ? "tiling on" : "tiling off");
    retile();
}

function cycleLayout() {
    cfg.layout = (cfg.layout + 1) % LAYOUT_COUNT;
    log("layout: " + LAYOUT_NAMES[cfg.layout]);
    retile();
}

function registerShortcuts() {
    var list = [
        ["TerminalTilerToggleFloat", "Terminal Tiler: Float / tile active terminal", "Meta+Shift+F", toggleFloat],
        ["TerminalTilerToggle", "Terminal Tiler: Turn tiling on / off", "Meta+Shift+T", toggleTiling],
        ["TerminalTilerFocusNext", "Terminal Tiler: Focus next terminal", "Meta+J", function () { focusStep(1); }],
        ["TerminalTilerFocusPrev", "Terminal Tiler: Focus previous terminal", "Meta+K", function () { focusStep(-1); }],
        ["TerminalTilerMoveNext", "Terminal Tiler: Move terminal forward", "Meta+Shift+J", function () { moveStep(1); }],
        ["TerminalTilerMovePrev", "Terminal Tiler: Move terminal back", "Meta+Shift+K", function () { moveStep(-1); }],
        ["TerminalTilerSwapMaster", "Terminal Tiler: Swap with master", "Meta+Return", swapWithMaster],
        ["TerminalTilerGrow", "Terminal Tiler: Grow master", "Meta+Shift+L", function () { changeRatio(RATIO_STEP); }],
        ["TerminalTilerShrink", "Terminal Tiler: Shrink master", "Meta+Shift+H", function () { changeRatio(-RATIO_STEP); }],
        ["TerminalTilerCycleLayout", "Terminal Tiler: Next layout", "", cycleLayout],
        ["TerminalTilerRetile", "Terminal Tiler: Re-tile now", "", retile]
    ];
    for (var i = 0; i < list.length; i++) {
        try {
            registerShortcut(list[i][0], list[i][1], list[i][2], list[i][3]);
        } catch (err) {
            log("could not register shortcut " + list[i][0] + ": " + err);
        }
    }
}

/* ------------------------------------------------------------------ start */

function init() {
    loadConfig();

    var list = workspace.windowList();
    for (var i = 0; i < list.length; i++) {
        hook(list[i]);
        if (isTerminal(list[i])) track(list[i], false);
    }
    retile();
    starting = false;

    workspace.windowAdded.connect(onWindowAdded);
    workspace.windowRemoved.connect(onWindowRemoved);
    workspace.currentDesktopChanged.connect(retile);
    workspace.currentActivityChanged.connect(retile);
    workspace.desktopsChanged.connect(retile);
    workspace.screensChanged.connect(retile);
    workspace.virtualScreenGeometryChanged.connect(retile);
    if (typeof options !== "undefined" && options.configChanged) {
        options.configChanged.connect(onConfigChanged);
    }

    registerShortcuts();
    log("started, tracking " + order.length + " terminal(s)");
}

init();
