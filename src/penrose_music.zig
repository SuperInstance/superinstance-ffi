//! Penrose music: Aperiodic rhythm and melody generation via cut-and-project.
//!
//! Ported from flux-tensor-midi/penrose.py — cut-and-project, Thue-Morse,
//! Fibonacci groove, and Padovan/plastic-number rhythms.

const std = @import("std");
const math = std.math;
const testing = std.testing;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

// ── Constants ────────────────────────────────────────────────────────

pub const PHI: f64 = 1.618033988749895;
pub const INV_PHI: f64 = 0.618033988749895;
pub const TWO_PI_OVER_5: f64 = 2.0 * math.pi / 5.0;
pub const PLASTIC_NUMBER: f64 = 1.324717957244746;

// ── Data types ───────────────────────────────────────────────────────

pub const TileType = enum { thick, thin, rejected };

pub const TileCoord = struct {
    x: f64,
    y: f64,
    tile_type: TileType,
};

pub const PenroseReport = struct {
    tile_count: usize,
    thick_count: usize,
    thin_count: usize,
    thick_thin_ratio: f64,
    ratio_ok: bool,
    five_fold_score: f64,
    five_fold_ok: bool,
    aperiodic: bool,
    min_nn_distance: f64,
    passes: bool,
};

// ── Linear algebra helpers ───────────────────────────────────────────

fn normalize(v: []f64) void {
    var norm: f64 = 0;
    for (v) |x| norm += x * x;
    norm = math.sqrt(norm);
    if (norm < 1e-12) return;
    for (v) |*x| x.* /= norm;
}

fn dot(a: []const f64, b: []const f64) f64 {
    var s: f64 = 0;
    for (a, 0..) |x, i| s += x * b[i];
    return s;
}

fn gramSchmidtComplement(
    allocator: Allocator,
    projection: []const []const f64,
    source_dim: usize,
) ![][]f64 {
    const target_dim = projection.len;
    var basis = std.ArrayList([]f64).init(allocator);
    defer basis.deinit();

    for (projection) |row| {
        const v = try allocator.dupe(f64, row[0..source_dim]);
        normalize(v);
        try basis.append(v);
    }

    for (0..source_dim) |i| {
        var e = try allocator.alloc(f64, source_dim);
        @memset(e, 0);
        e[i] = 1.0;

        for (basis.items) |b| {
            const d = dot(e, b);
            for (e, 0..) |*val, k| val.* -= d * b[k];
        }
        normalize(e);

        var is_zero = true;
        for (e) |val| {
            if (@abs(val) > 1e-12) { is_zero = false; break; }
        }
        if (!is_zero and basis.items.len < source_dim) {
            try basis.append(e);
        } else {
            allocator.free(e);
        }
    }

    // Free the projection-row copies (indices 0..target_dim) — we only return perp rows
    for (0..target_dim) |i| {
        allocator.free(basis.items[i]);
    }

    const perp_dim = source_dim - target_dim;
    const perp = try allocator.alloc([]f64, perp_dim);
    for (0..perp_dim) |i| {
        if (target_dim + i < basis.items.len) {
            perp[i] = basis.items[target_dim + i];
        } else {
            perp[i] = try allocator.alloc(f64, source_dim);
            @memset(perp[i], 0);
        }
    }
    return perp;
}

// ── Cut-and-Project Compiler ─────────────────────────────────────────

pub const CutAndProject = struct {
    source_dim: usize,
    target_dim: usize,
    projection: [][]f64,
    perp_projection: [][]f64,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, source_dim: usize, target_dim: usize) !Self {
        assert(target_dim <= source_dim);
        const projection = try allocator.alloc([]f64, target_dim);
        for (projection) |*row| {
            row.* = try allocator.alloc(f64, source_dim);
            @memset(row.*, 0);
        }
        return Self{
            .source_dim = source_dim,
            .target_dim = target_dim,
            .projection = projection,
            .perp_projection = &[_][]f64{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        // Free perp_projection rows
        if (self.perp_projection.len > 0) {
            for (self.perp_projection) |row| {
                self.allocator.free(row);
            }
            self.allocator.free(self.perp_projection);
        }
        // Free projection rows
        for (self.projection) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(self.projection);
    }

    pub fn withGoldenProjection(self: *Self) !void {
        std.debug.assert(self.source_dim == 5 and self.target_dim == 2);
        for (0..5) |k| {
            const angle: f64 = @as(f64, @floatFromInt(k)) * TWO_PI_OVER_5;
            self.projection[0][k] = math.cos(angle);
            self.projection[1][k] = math.sin(angle);
        }
        try self.recomputePerp();
    }

    pub fn recomputePerp(self: *Self) !void {
        const const_proj = try self.allocator.alloc([]const f64, self.target_dim);
        for (0..self.target_dim) |i| {
            const_proj[i] = self.projection[i];
        }
        self.perp_projection = try gramSchmidtComplement(self.allocator, const_proj, self.source_dim);
        self.allocator.free(const_proj);
    }

    const WindowFn = *const fn ([]const f64) bool;

    fn defaultWindow(perp: []const f64) bool {
        for (perp) |v| {
            if (@abs(v) >= INV_PHI) return false;
        }
        return true;
    }

    pub fn generate(self: *Self, allocator: Allocator, range: i32) ![]TileCoord {
        return self.generateWithWindow(allocator, range, defaultWindow);
    }

    pub fn generateWithWindow(self: *Self, allocator: Allocator, range: i32, window: WindowFn) ![]TileCoord {
        var tiles = std.ArrayList(TileCoord).init(allocator);

        const perp_dim = self.source_dim - self.target_dim;
        const perp_buf = try allocator.alloc(f64, perp_dim);
        defer allocator.free(perp_buf);
        const target_buf = try allocator.alloc(f64, self.target_dim);
        defer allocator.free(target_buf);

        const r = @as(usize, @intCast(range));
        const side = 2 * r + 1;
        const total = std.math.pow(usize, side, self.source_dim);
        var coords = try allocator.alloc(i32, self.source_dim);
        defer allocator.free(coords);

        for (0..total) |idx| {
            var tmp = idx;
            for (0..self.source_dim) |d| {
                coords[d] = @as(i32, @intCast(tmp % side)) - @as(i32, @intCast(r));
                tmp /= side;
            }

            // Project to perpendicular space
            for (perp_buf, 0..) |*v, i| {
                var s: f64 = 0;
                for (self.perp_projection[i], 0..) |val, j| {
                    s += val * @as(f64, @floatFromInt(coords[j]));
                }
                v.* = s;
            }

            if (!window(perp_buf)) continue;

            // Project to target space
            for (target_buf, 0..) |*v, i| {
                var s: f64 = 0;
                for (self.projection[i], 0..) |val, j| {
                    s += val * @as(f64, @floatFromInt(coords[j]));
                }
                v.* = s;
            }

            const tile_type = classifyTile(coords);
            try tiles.append(.{
                .x = target_buf[0],
                .y = if (self.target_dim > 1) target_buf[1] else 0.0,
                .tile_type = tile_type,
            });
        }

        return tiles.toOwnedSlice();
    }

    fn classifyTile(coords: []const i32) TileType {
        var s: f64 = 0;
        for (coords) |v| s += @abs(@as(f64, @floatFromInt(v)));
        s *= INV_PHI;
        const frac = s - @floor(s);
        return if (frac < INV_PHI) .thick else .thin;
    }

    pub fn verify(tiles: []const TileCoord) PenroseReport {
        var thick: usize = 0;
        var thin: usize = 0;
        for (tiles) |t| {
            switch (t.tile_type) {
                .thick => thick += 1,
                .thin => thin += 1,
                else => {},
            }
        }
        const total = thick + thin;
        const ratio = if (thin > 0) @as(f64, @floatFromInt(thick)) / @as(f64, @floatFromInt(thin)) else if (thick > 0) math.inf(f64) else 0.0;
        const ratio_ok = total > 0 and @abs(ratio - INV_PHI) < 0.15;
        const five_fold = fiveFoldScore(tiles);
        const five_fold_ok = five_fold > 0.3;
        const aperiodic = checkAperiodic(tiles);
        const min_nn = minNN(tiles);

        return PenroseReport{
            .tile_count = total,
            .thick_count = thick,
            .thin_count = thin,
            .thick_thin_ratio = ratio,
            .ratio_ok = ratio_ok,
            .five_fold_score = five_fold,
            .five_fold_ok = five_fold_ok,
            .aperiodic = aperiodic,
            .min_nn_distance = min_nn,
            .passes = ratio_ok and five_fold_ok and aperiodic and total > 0,
        };
    }

    fn fiveFoldScore(tiles: []const TileCoord) f64 {
        if (tiles.len == 0) return 1.0;
        const limit = @min(tiles.len, 500);
        const cos_a = math.cos(TWO_PI_OVER_5);
        const sin_a = math.sin(TWO_PI_OVER_5);
        const threshold: f64 = 0.5;
        var matched: usize = 0;

        for (tiles[0..limit]) |t| {
            const rx = t.x * cos_a - t.y * sin_a;
            const ry = t.x * sin_a + t.y * cos_a;
            for (tiles[0..limit]) |u| {
                const dx = u.x - rx;
                const dy = u.y - ry;
                if (@sqrt(dx * dx + dy * dy) < threshold) {
                    matched += 1;
                    break;
                }
            }
        }
        return @as(f64, @floatFromInt(matched)) / @as(f64, @floatFromInt(limit));
    }

    fn checkAperiodic(tiles: []const TileCoord) bool {
        if (tiles.len < 10) return true;
        const n_bins: usize = 50;
        var bins = [_]usize{0} ** 50;
        var x_min: f64 = math.inf(f64);
        var x_max: f64 = -math.inf(f64);
        for (tiles) |t| {
            if (t.x < x_min) x_min = t.x;
            if (t.x > x_max) x_max = t.x;
        }
        const span = @max(x_max - x_min, 1e-12);
        for (tiles) |t| {
            const idx = @min(@as(usize, @intFromFloat(@round((t.x - x_min) / span * @as(f64, @floatFromInt(n_bins - 1))))), n_bins - 1);
            bins[idx] += 1;
        }
        for (1..10) |period| {
            var all_eq = true;
            for (period..n_bins) |i| {
                if (bins[i] != bins[i - period]) { all_eq = false; break; }
            }
            if (all_eq) return false;
        }
        return true;
    }

    fn minNN(tiles: []const TileCoord) f64 {
        const limit = @min(tiles.len, 500);
        if (limit < 2) return 0.0;
        var min_d: f64 = math.inf(f64);
        for (0..limit) |i| {
            for (i + 1..limit) |j| {
                const dx = tiles[i].x - tiles[j].x;
                const dy = tiles[i].y - tiles[j].y;
                const d = @sqrt(dx * dx + dy * dy);
                if (d < min_d) min_d = d;
            }
        }
        return if (min_d != math.inf(f64)) min_d else 0.0;
    }
};

// ── Penrose rhythm — aperiodic drum patterns ──────────────────────────

pub fn penroseRhythm(allocator: Allocator, range: i32, groove_width: f64) ![]bool {
    _ = groove_width;
    var compiler = try CutAndProject.init(allocator, 5, 2);
    defer compiler.deinit();
    try compiler.withGoldenProjection();
    const tiles = try compiler.generate(allocator, range);
    defer allocator.free(tiles);

    if (tiles.len == 0) return &[_]bool{};
    var rhythm = std.ArrayList(bool).init(allocator);
    for (tiles) |t| {
        try rhythm.append(t.tile_type == .thick);
    }
    return rhythm.toOwnedSlice();
}

// ── Penrose melody — tile positions to pitches ───────────────────────

pub fn penroseMelody(allocator: Allocator, scale: []const i32, range: i32) ![]i32 {
    var compiler = try CutAndProject.init(allocator, 5, 2);
    defer compiler.deinit();
    try compiler.withGoldenProjection();
    const tiles = try compiler.generate(allocator, range);
    defer allocator.free(tiles);

    if (tiles.len == 0) return &[_]i32{};

    var y_min: f64 = math.inf(f64);
    var y_max: f64 = -math.inf(f64);
    for (tiles) |t| {
        if (t.y < y_min) y_min = t.y;
        if (t.y > y_max) y_max = t.y;
    }
    const y_span = @max(y_max - y_min, 1e-12);

    var pitches = std.ArrayList(i32).init(allocator);
    for (tiles) |t| {
        const y_norm = (t.y - y_min) / y_span;
        var scale_idx = @as(usize, @intFromFloat(y_norm * @as(f64, @floatFromInt(scale.len - 1))));
        scale_idx = @min(scale_idx, scale.len - 1);
        const pitch = 60 + scale[scale_idx];
        try pitches.append(pitch);
    }
    return pitches.toOwnedSlice();
}

// ── Thue-Morse sequence ──────────────────────────────────────────────

pub fn thueMorse(allocator: Allocator, n: usize) ![]u8 {
    const seq = try allocator.alloc(u8, n);
    for (0..n) |i| {
        seq[i] = @as(u8, @popCount(i) % 2);
    }
    return seq;
}

// ── Fibonacci rhythm ─────────────────────────────────────────────────

pub fn fibonacciGroove(allocator: Allocator, n_beats: usize) ![]bool {
    if (n_beats == 0) return &[_]bool{};

    var fibs = std.ArrayList(usize).init(allocator);
    defer fibs.deinit();
    try fibs.append(1);
    try fibs.append(1);
    while (true) {
        const next = fibs.items[fibs.items.len - 1] + fibs.items[fibs.items.len - 2];
        try fibs.append(next);
        var total: usize = 0;
        for (fibs.items) |f| total += f;
        if (total >= n_beats) break;
    }

    var rhythm = std.ArrayList(bool).init(allocator);
    var pos: usize = 0;
    for (fibs.items) |group_size| {
        for (0..group_size) |i| {
            if (pos >= n_beats) break;
            try rhythm.append(i == 0);
            pos += 1;
        }
        if (pos >= n_beats) break;
    }
    return rhythm.toOwnedSlice();
}

// ── Plastic number (Padovan) rhythm ──────────────────────────────────

pub fn plasticRhythm(allocator: Allocator, n_beats: usize) ![]bool {
    if (n_beats == 0) return &[_]bool{};

    var pads = std.ArrayList(usize).init(allocator);
    defer pads.deinit();
    try pads.append(1);
    try pads.append(1);
    try pads.append(1);
    while (true) {
        const len = pads.items.len;
        const next = pads.items[len - 2] + pads.items[len - 3];
        try pads.append(next);
        var total: usize = 0;
        for (pads.items) |p| total += p;
        if (total >= n_beats) break;
    }

    var rhythm = std.ArrayList(bool).init(allocator);
    var pos: usize = 0;
    for (pads.items) |group_size| {
        for (0..group_size) |i| {
            if (pos >= n_beats) break;
            try rhythm.append(i == 0);
            pos += 1;
        }
        if (pos >= n_beats) break;
    }
    return rhythm.toOwnedSlice();
}

// ── Fibonacci sequence (utility) ─────────────────────────────────────

pub fn fibonacciSequence(allocator: Allocator, n: usize) ![]usize {
    if (n == 0) return try allocator.alloc(usize, 0);
    const fibs = try allocator.alloc(usize, n);
    if (n >= 1) fibs[0] = 1;
    if (n >= 2) fibs[1] = 1;
    for (2..n) |i| fibs[i] = fibs[i - 1] + fibs[i - 2];
    return fibs;
}

// ── Padovan sequence (utility) ───────────────────────────────────────

pub fn padovanSequence(allocator: Allocator, n: usize) ![]usize {
    if (n == 0) return try allocator.alloc(usize, 0);
    const pads = try allocator.alloc(usize, n);
    if (n >= 1) pads[0] = 1;
    if (n >= 2) pads[1] = 1;
    if (n >= 3) pads[2] = 1;
    for (3..n) |i| pads[i] = pads[i - 2] + pads[i - 3];
    return pads;
}

// ══════════════════════════════════════════════════════════════════════
// Tests
// ══════════════════════════════════════════════════════════════════════

test "CutAndProject: golden projection produces tiles" {
    const allocator = testing.allocator;
    var compiler = try CutAndProject.init(allocator, 5, 2);
    defer compiler.deinit();
    try compiler.withGoldenProjection();
    const tiles = try compiler.generate(allocator, 3);
    defer allocator.free(tiles);
    try testing.expect(tiles.len > 0);
}

test "CutAndProject: reject-all window gives zero tiles" {
    const allocator = testing.allocator;
    var compiler = try CutAndProject.init(allocator, 5, 2);
    defer compiler.deinit();
    try compiler.withGoldenProjection();
    const tiles = try compiler.generateWithWindow(allocator, 3, struct {
        fn reject(_: []const f64) bool {
            return false;
        }
    }.reject);
    defer allocator.free(tiles);
    try testing.expectEqual(@as(usize, 0), tiles.len);
}

test "CutAndProject: tile types are valid" {
    const allocator = testing.allocator;
    var compiler = try CutAndProject.init(allocator, 5, 2);
    defer compiler.deinit();
    try compiler.withGoldenProjection();
    const tiles = try compiler.generate(allocator, 4);
    defer allocator.free(tiles);
    for (tiles) |t| {
        try testing.expect(t.tile_type == .thick or t.tile_type == .thin);
    }
}

test "CutAndProject: verify report has tiles" {
    const allocator = testing.allocator;
    var compiler = try CutAndProject.init(allocator, 5, 2);
    defer compiler.deinit();
    try compiler.withGoldenProjection();
    const tiles = try compiler.generate(allocator, 5);
    defer allocator.free(tiles);
    const report = CutAndProject.verify(tiles);
    try testing.expect(report.tile_count > 0);
    try testing.expect(report.thick_thin_ratio > 0.0);
}

test "CutAndProject: aperiodicity" {
    const allocator = testing.allocator;
    var compiler = try CutAndProject.init(allocator, 5, 2);
    defer compiler.deinit();
    try compiler.withGoldenProjection();
    const tiles = try compiler.generate(allocator, 6);
    defer allocator.free(tiles);
    const report = CutAndProject.verify(tiles);
    try testing.expect(report.aperiodic);
}

test "CutAndProject: more range gives more tiles" {
    const allocator = testing.allocator;
    var compiler = try CutAndProject.init(allocator, 5, 2);
    defer compiler.deinit();
    try compiler.withGoldenProjection();
    const t1 = try compiler.generate(allocator, 2);
    defer allocator.free(t1);
    const t2 = try compiler.generate(allocator, 4);
    defer allocator.free(t2);
    try testing.expect(t2.len >= t1.len);
}

test "CutAndProject: five-fold symmetry" {
    const allocator = testing.allocator;
    var compiler = try CutAndProject.init(allocator, 5, 2);
    defer compiler.deinit();
    try compiler.withGoldenProjection();
    const tiles = try compiler.generate(allocator, 6);
    defer allocator.free(tiles);
    const report = CutAndProject.verify(tiles);
    try testing.expect(report.five_fold_ok);
}

test "CutAndProject: min_nn positive" {
    const allocator = testing.allocator;
    var compiler = try CutAndProject.init(allocator, 5, 2);
    defer compiler.deinit();
    try compiler.withGoldenProjection();
    const tiles = try compiler.generate(allocator, 4);
    defer allocator.free(tiles);
    if (tiles.len > 1) {
        const report = CutAndProject.verify(tiles);
        try testing.expect(report.min_nn_distance > 0.0);
    }
}

test "CutAndProject: thick and thin both present" {
    const allocator = testing.allocator;
    var compiler = try CutAndProject.init(allocator, 5, 2);
    defer compiler.deinit();
    try compiler.withGoldenProjection();
    const tiles = try compiler.generate(allocator, 8);
    defer allocator.free(tiles);
    const report = CutAndProject.verify(tiles);
    try testing.expect(report.thick_count > 0);
    try testing.expect(report.thin_count > 0);
}

test "CutAndProject: range zero valid" {
    const allocator = testing.allocator;
    var compiler = try CutAndProject.init(allocator, 5, 2);
    defer compiler.deinit();
    try compiler.withGoldenProjection();
    const tiles = try compiler.generate(allocator, 0);
    defer allocator.free(tiles);
    for (tiles) |t| {
        try testing.expect(t.tile_type == .thick or t.tile_type == .thin);
    }
}

test "penroseRhythm: generates hits" {
    const allocator = testing.allocator;
    const rhythm = try penroseRhythm(allocator, 3, 0.5);
    defer allocator.free(rhythm);
    try testing.expect(rhythm.len > 0);
}

test "penroseMelody: generates pitches" {
    const allocator = testing.allocator;
    const scale = [_]i32{ 0, 2, 4, 7, 9 };
    const pitches = try penroseMelody(allocator, &scale, 3);
    defer allocator.free(pitches);
    try testing.expect(pitches.len > 0);
    for (pitches) |p| {
        try testing.expect(p >= 0);
        try testing.expect(p <= 127);
    }
}

test "Penrose melody: custom scale" {
    const allocator = testing.allocator;
    const scale = [_]i32{ 0, 3, 5, 7, 10 };
    const pitches = try penroseMelody(allocator, &scale, 4);
    defer allocator.free(pitches);
    try testing.expect(pitches.len > 0);
    for (pitches) |p| {
        const pc = @mod(p, 12);
        var found = false;
        for (scale) |s| {
            if (pc == s) { found = true; break; }
        }
        try testing.expect(found);
    }
}

test "Thue-Morse: first 8 terms" {
    const allocator = testing.allocator;
    const seq = try thueMorse(allocator, 8);
    defer allocator.free(seq);
    const expected = [_]u8{ 0, 1, 1, 0, 1, 0, 0, 1 };
    for (expected, 0..) |e, i| {
        try testing.expectEqual(e, seq[i]);
    }
}

test "Thue-Morse: parity property t(2n)=t(n)" {
    const allocator = testing.allocator;
    const seq = try thueMorse(allocator, 100);
    defer allocator.free(seq);
    for (0..50) |i| {
        try testing.expectEqual(seq[i], seq[2 * i]);
        try testing.expectEqual(1 - seq[i], seq[2 * i + 1]);
    }
}

test "Fibonacci sequence: first 8" {
    const allocator = testing.allocator;
    const fibs = try fibonacciSequence(allocator, 8);
    defer allocator.free(fibs);
    const expected = [_]usize{ 1, 1, 2, 3, 5, 8, 13, 21 };
    for (expected, 0..) |e, i| {
        try testing.expectEqual(e, fibs[i]);
    }
}

test "Fibonacci groove: generates rhythm" {
    const allocator = testing.allocator;
    const rhythm = try fibonacciGroove(allocator, 20);
    defer allocator.free(rhythm);
    try testing.expect(rhythm.len > 0);
    try testing.expect(rhythm[0]);
}

test "Padovan sequence: first 10" {
    const allocator = testing.allocator;
    const pads = try padovanSequence(allocator, 10);
    defer allocator.free(pads);
    const expected = [_]usize{ 1, 1, 1, 2, 2, 3, 4, 5, 7, 9 };
    for (expected, 0..) |e, i| {
        try testing.expectEqual(e, pads[i]);
    }
}

test "Plastic rhythm: generates rhythm" {
    const allocator = testing.allocator;
    const rhythm = try plasticRhythm(allocator, 20);
    defer allocator.free(rhythm);
    try testing.expect(rhythm.len > 0);
    try testing.expect(rhythm[0]);
}
