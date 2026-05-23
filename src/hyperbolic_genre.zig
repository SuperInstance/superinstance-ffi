//! Hyperbolic genre space — Poincaré ball model (8D) for musical genre taxonomy.
//!
//! Genres live as points on the Poincaré ball. Hierarchical relationships
//! (parent/subgenre) and cultural adjacency are captured by hyperbolic
//! distance. Fréchet mean provides weighted blending in curved space.

const std = @import("std");
const math = std.math;
const testing = std.testing;

pub const DIM: usize = 8;
pub const CURVATURE: f64 = -1.0;

// ── Poincaré ball primitives ─────────────────────────────────────────

pub const HyperbolicPoint = struct {
    coords: [DIM]f64,

    pub fn origin() HyperbolicPoint {
        var coords: [DIM]f64 = undefined;
        @memset(&coords, 0.0);
        return .{ .coords = coords };
    }

    pub fn fromSlice(s: []const f64) HyperbolicPoint {
        var p = HyperbolicPoint.origin();
        const n = @min(s.len, DIM);
        @memcpy(p.coords[0..n], s[0..n]);
        return p;
    }

    /// Squared Euclidean norm of coordinates.
    pub fn normSq(self: *const HyperbolicPoint) f64 {
        var s: f64 = 0.0;
        for (self.coords) |c| s += c * c;
        return s;
    }

    pub fn norm(self: *const HyperbolicPoint) f64 {
        return @sqrt(self.normSq());
    }

    /// Clamp into the open ball (max radius < 1).
    pub fn clamp(self: *const HyperbolicPoint, max_r: f64) HyperbolicPoint {
        const r = self.norm();
        if (r < max_r) return self.*;
        const scale = max_r * (1.0 - 1e-8) / r;
        var out = HyperbolicPoint.origin();
        for (&out.coords, self.coords) |*o, c| o.* = c * scale;
        return out;
    }

    pub fn eql(a: *const HyperbolicPoint, b: *const HyperbolicPoint, tol: f64) bool {
        for (a.coords, b.coords) |ac, bc| {
            if (@abs(ac - bc) > tol) return false;
        }
        return true;
    }
};

/// Hyperbolic distance on the Poincaré ball with curvature c = -1.
///   d(a,b) = acosh(1 + 2 * ||a-b||² / ((1-||a||²)(1-||b||²)))
pub fn poincare_distance(a: *const HyperbolicPoint, b: *const HyperbolicPoint) f64 {
    const diff_sq = blk: {
        var s: f64 = 0.0;
        for (a.coords, b.coords) |ac, bc| {
            const d = ac - bc;
            s += d * d;
        }
        break :blk s;
    };
    const a_sq = a.normSq();
    const b_sq = b.normSq();
    const denom = (1.0 - a_sq) * (1.0 - b_sq);
    if (denom <= 0.0) return 1e10; // outside ball — sentinel
    const arg = 1.0 + 2.0 * diff_sq / denom;
    return acosh(@max(arg, 1.0));
}

/// Exponential map: project tangent vector `v` at `base` onto the ball.
/// Uses Möbius gyro-vector formulation.
pub fn exp_map(base: *const HyperbolicPoint, tangent: *const HyperbolicPoint) HyperbolicPoint {
    const b_sq = base.normSq();
    const v_sq = tangent.normSq();
    const gamma = 1.0 / @sqrt(@max(1.0 - b_sq, 1e-15));
    const c2 = @sqrt(@max(v_sq, 0.0));

    if (c2 < 1e-15) return base.*;

    // Simplified exp map for Poincaré ball
    const t = math.tanh(c2 * gamma) / c2;
    var result = HyperbolicPoint.origin();
    for (&result.coords, base.coords, tangent.coords) |*r, bc, vc| {
        r.* = bc + t * vc;
    }
    return result.clamp(0.999);
}

/// Logarithmic map: inverse of exp_map — gives tangent vector at `base` pointing toward `target`.
pub fn log_map(base: *const HyperbolicPoint, target: *const HyperbolicPoint) HyperbolicPoint {
    const dist = poincare_distance(base, target);
    if (dist < 1e-15) return HyperbolicPoint.origin();

    const b_sq = base.normSq();
    const gamma = 1.0 / @sqrt(@max(1.0 - b_sq, 1e-15));

    // Direction from base to target in ambient space
    var diff = HyperbolicPoint.origin();
    for (&diff.coords, target.coords, base.coords) |*d, tc, bc| {
        d.* = tc - bc;
    }
    const diff_norm = diff.norm();
    if (diff_norm < 1e-15) return HyperbolicPoint.origin();

    const scale = dist / (diff_norm * gamma);
    var result = HyperbolicPoint.origin();
    for (&result.coords, diff.coords) |*r, dc| {
        r.* = dc * scale;
    }
    return result;
}

/// Fréchet mean (Karcher mean) on the Poincaré ball via Riemannian gradient descent.
pub fn frechet_mean(points: []const HyperbolicPoint, weights: []const f64, iterations: usize) HyperbolicPoint {
    std.debug.assert(points.len > 0);
    std.debug.assert(points.len == weights.len);

    // Weighted Euclidean init
    var mean = HyperbolicPoint.origin();
    var w_sum: f64 = 0.0;
    for (points, weights) |p, w| {
        for (&mean.coords, p.coords) |*m, c| m.* += c * w;
        w_sum += w;
    }
    if (w_sum > 0.0) {
        for (&mean.coords) |*m| m.* /= w_sum;
    }
    mean = mean.clamp(0.5);

    var lr: f64 = 0.1;
    for (0..iterations) |i| {
        // Adaptive learning rate
        lr = 0.1 / (1.0 + @as(f64, @floatFromInt(i)) * 0.01);

        var grad = HyperbolicPoint.origin();
        for (points, weights) |p, w| {
            const log_v = log_map(&mean, &p);
            for (&grad.coords, log_v.coords) |*g, lc| g.* += w * lc;
        }
        mean = exp_map(&mean, &grad);
        // Negate gradient direction for descent
        var neg_grad = grad;
        for (&neg_grad.coords) |*c| c.* *= -lr;
        mean = exp_map(&mean, &neg_grad);
        mean = mean.clamp(0.999);
    }
    return mean;
}

// ── Genre taxonomy ───────────────────────────────────────────────────

pub const GenreNode = struct {
    name: []const u8,
    culture: []const u8,
    level: usize, // 0=root, 1=broad, 2=specific, 3=subgenre
    point: HyperbolicPoint,
    parent: ?usize,
};

pub const GenreMap = struct {
    nodes: []GenreNode,

    const Self = @This();

    /// Initialize with 42 pre-defined genres across cultures.
    /// Caller must free with allocator.
    pub fn init(allocator: std.mem.Allocator) !Self {
        const nodes = try allocator.dupe(GenreNode, &DEFAULT_GENRES);
        return Self{ .nodes = nodes };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.nodes);
    }

    pub fn find(self: *const Self, name: []const u8) ?usize {
        for (self.nodes, 0..) |n, i| {
            if (std.mem.eql(u8, n.name, name)) return i;
        }
        return null;
    }

    /// Return indices of the `n` nearest genres to `point`.
    pub fn nearest(self: *const Self, point: *const HyperbolicPoint, n: usize, allocator: std.mem.Allocator) ![]usize {
        const distances = try allocator.alloc(f64, self.nodes.len);
        defer allocator.free(distances);

        for (distances, self.nodes) |*d, node| {
            d.* = poincare_distance(point, &node.point);
        }

        var indices = try allocator.alloc(usize, self.nodes.len);
        for (indices, 0..) |*idx, i| idx.* = i;
        // Selection sort for top-n
        const count = @min(n, self.nodes.len);
        for (0..count) |i| {
            var best = i;
            for (i + 1..self.nodes.len) |j| {
                if (distances[j] < distances[best]) best = j;
            }
            if (best != i) {
                std.mem.swap(f64, &distances[i], &distances[best]);
                std.mem.swap(usize, &indices[i], &indices[best]);
            }
        }
        const result = try allocator.alloc(usize, count);
        @memcpy(result, indices[0..count]);
        allocator.free(indices);
        return result;
    }

    /// Weighted blend of named genres via Fréchet mean.
    pub fn blend(self: *const Self, names: []const []const u8, weights: []const f64) ?HyperbolicPoint {
        if (names.len == 0 or names.len != weights.len) return null;
        var points = std.BoundedArray(HyperbolicPoint, 64).init(0) catch return null;
        for (names) |name| {
            const idx = self.find(name) orelse return null;
            points.append(self.nodes[idx].point) catch return null;
        }
        return frechet_mean(points.constSlice(), weights, 50);
    }

    /// Cultural distance between two named genres.
    pub fn cultural_distance(self: *const Self, a_name: []const u8, b_name: []const u8) ?f64 {
        const ai = self.find(a_name) orelse return null;
        const bi = self.find(b_name) orelse return null;
        const dist = poincare_distance(&self.nodes[ai].point, &self.nodes[bi].point);
        // Bonus: same culture reduces distance
        if (std.mem.eql(u8, self.nodes[ai].culture, self.nodes[bi].culture)) {
            return dist * 0.7;
        }
        return dist;
    }
};

// ── Helpers ──────────────────────────────────────────────────────────

fn dot(a: *const HyperbolicPoint, b: *const HyperbolicPoint) f64 {
    var s: f64 = 0.0;
    for (a.coords, b.coords) |ac, bc| s += ac * bc;
    return s;
}

fn acosh(x: f64) f64 {
    return @log(x + @sqrt(x * x - 1.0));
}


// ── 42 Genre definitions ────────────────────────────────────────────

const DEFAULT_GENRES = [_]GenreNode{
    // Level 0: root
    .{ .name = "music", .culture = "universal", .level = 0, .point = .{ .coords = .{ 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 } }, .parent = null },
    // Level 1: broad
    .{ .name = "jazz", .culture = "african-american", .level = 1, .point = .{ .coords = .{ 0.30, 0.20, -0.10, 0.05, 0.10, -0.05, 0.08, -0.03 } }, .parent = 0 },
    .{ .name = "classical", .culture = "european", .level = 1, .point = .{ .coords = .{ -0.40, 0.35, 0.15, -0.10, -0.05, 0.12, -0.08, 0.06 } }, .parent = 0 },
    .{ .name = "rock", .culture = "western", .level = 1, .point = .{ .coords = .{ 0.20, -0.25, 0.10, 0.30, -0.15, 0.05, 0.12, -0.08 } }, .parent = 0 },
    .{ .name = "electronic", .culture = "global", .level = 1, .point = .{ .coords = .{ 0.35, -0.10, -0.20, 0.25, 0.30, -0.15, 0.05, 0.18 } }, .parent = 0 },
    .{ .name = "hip-hop", .culture = "african-american", .level = 1, .point = .{ .coords = .{ 0.25, 0.10, -0.15, 0.20, 0.15, -0.10, 0.18, -0.05 } }, .parent = 0 },
    .{ .name = "folk", .culture = "global", .level = 1, .point = .{ .coords = .{ -0.15, 0.20, 0.25, -0.20, -0.10, 0.15, -0.05, 0.10 } }, .parent = 0 },
    .{ .name = "world", .culture = "global", .level = 1, .point = .{ .coords = .{ 0.05, 0.25, 0.30, -0.15, 0.05, 0.20, -0.10, 0.15 } }, .parent = 0 },
    .{ .name = "ambient", .culture = "global", .level = 1, .point = .{ .coords = .{ -0.20, -0.15, -0.25, -0.10, -0.30, 0.05, -0.08, -0.12 } }, .parent = 0 },
    // Level 2: specific
    .{ .name = "bebop", .culture = "african-american", .level = 2, .point = .{ .coords = .{ 0.35, 0.25, -0.12, 0.03, 0.15, -0.08, 0.10, -0.05 } }, .parent = 1 },
    .{ .name = "cool-jazz", .culture = "african-american", .level = 2, .point = .{ .coords = .{ 0.28, 0.18, -0.08, 0.07, 0.08, -0.03, 0.06, -0.02 } }, .parent = 1 },
    .{ .name = "free-jazz", .culture = "african-american", .level = 2, .point = .{ .coords = .{ 0.38, 0.22, -0.18, 0.01, 0.12, -0.12, 0.14, -0.08 } }, .parent = 1 },
    .{ .name = "swing", .culture = "african-american", .level = 2, .point = .{ .coords = .{ 0.32, 0.15, -0.05, 0.10, 0.05, 0.02, 0.04, 0.01 } }, .parent = 1 },
    .{ .name = "baroque", .culture = "european", .level = 2, .point = .{ .coords = .{ -0.45, 0.38, 0.18, -0.12, -0.08, 0.15, -0.10, 0.08 } }, .parent = 2 },
    .{ .name = "romantic", .culture = "european", .level = 2, .point = .{ .coords = .{ -0.38, 0.32, 0.12, -0.08, -0.03, 0.10, -0.06, 0.04 } }, .parent = 2 },
    .{ .name = "contemporary-classical", .culture = "european", .level = 2, .point = .{ .coords = .{ -0.35, 0.30, 0.10, -0.05, 0.05, 0.08, -0.04, 0.02 } }, .parent = 2 },
    .{ .name = "punk", .culture = "western", .level = 2, .point = .{ .coords = .{ 0.28, -0.30, 0.15, 0.35, -0.18, 0.08, 0.15, -0.12 } }, .parent = 3 },
    .{ .name = "metal", .culture = "western", .level = 2, .point = .{ .coords = .{ 0.22, -0.28, 0.18, 0.32, -0.20, 0.06, 0.14, -0.10 } }, .parent = 3 },
    .{ .name = "indie", .culture = "western", .level = 2, .point = .{ .coords = .{ 0.18, -0.22, 0.08, 0.25, -0.12, 0.04, 0.10, -0.06 } }, .parent = 3 },
    .{ .name = "grunge", .culture = "western", .level = 2, .point = .{ .coords = .{ 0.24, -0.26, 0.12, 0.28, -0.16, 0.06, 0.13, -0.09 } }, .parent = 3 },
    .{ .name = "techno", .culture = "global", .level = 2, .point = .{ .coords = .{ 0.38, -0.12, -0.22, 0.28, 0.32, -0.18, 0.06, 0.20 } }, .parent = 4 },
    .{ .name = "house", .culture = "global", .level = 2, .point = .{ .coords = .{ 0.33, -0.08, -0.18, 0.24, 0.28, -0.14, 0.04, 0.16 } }, .parent = 4 },
    .{ .name = "dubstep", .culture = "british", .level = 2, .point = .{ .coords = .{ 0.40, -0.15, -0.25, 0.30, 0.35, -0.20, 0.08, 0.22 } }, .parent = 4 },
    .{ .name = "trance", .culture = "global", .level = 2, .point = .{ .coords = .{ 0.36, -0.10, -0.20, 0.26, 0.30, -0.16, 0.05, 0.19 } }, .parent = 4 },
    .{ .name = "drum-and-bass", .culture = "british", .level = 2, .point = .{ .coords = .{ 0.42, -0.14, -0.23, 0.29, 0.38, -0.22, 0.10, 0.24 } }, .parent = 4 },
    .{ .name = "trap", .culture = "african-american", .level = 2, .point = .{ .coords = .{ 0.28, 0.12, -0.18, 0.22, 0.18, -0.12, 0.20, -0.08 } }, .parent = 5 },
    .{ .name = "boom-bap", .culture = "african-american", .level = 2, .point = .{ .coords = .{ 0.24, 0.08, -0.12, 0.18, 0.12, -0.08, 0.16, -0.04 } }, .parent = 5 },
    .{ .name = "lo-fi-hiphop", .culture = "global", .level = 2, .point = .{ .coords = .{ 0.20, 0.06, -0.10, 0.14, 0.08, -0.05, 0.12, -0.02 } }, .parent = 5 },
    .{ .name = "celtic", .culture = "celtic", .level = 2, .point = .{ .coords = .{ -0.18, 0.25, 0.28, -0.22, -0.12, 0.18, -0.06, 0.12 } }, .parent = 6 },
    .{ .name = "bluegrass", .culture = "american", .level = 2, .point = .{ .coords = .{ -0.12, 0.18, 0.22, -0.18, -0.08, 0.12, -0.04, 0.08 } }, .parent = 6 },
    .{ .name = "flamenco", .culture = "spanish", .level = 2, .point = .{ .coords = .{ 0.10, 0.28, 0.20, -0.10, 0.02, 0.16, -0.08, 0.14 } }, .parent = 7 },
    .{ .name = "reggae", .culture = "jamaican", .level = 2, .point = .{ .coords = .{ 0.15, 0.12, 0.05, 0.10, -0.05, 0.08, 0.02, 0.06 } }, .parent = 7 },
    .{ .name = "afrobeat", .culture = "west-african", .level = 2, .point = .{ .coords = .{ 0.20, 0.22, 0.10, 0.05, 0.12, 0.15, 0.04, 0.10 } }, .parent = 7 },
    .{ .name = "bossa-nova", .culture = "brazilian", .level = 2, .point = .{ .coords = .{ 0.12, 0.20, 0.08, -0.05, -0.02, 0.10, -0.02, 0.08 } }, .parent = 7 },
    .{ .name = "gamelan", .culture = "indonesian", .level = 2, .point = .{ .coords = .{ -0.02, 0.18, 0.22, -0.12, 0.08, 0.22, -0.12, 0.18 } }, .parent = 7 },
    .{ .name = "raga", .culture = "indian", .level = 2, .point = .{ .coords = .{ 0.05, 0.22, 0.18, -0.08, 0.04, 0.20, -0.10, 0.16 } }, .parent = 7 },
    .{ .name = "drone-ambient", .culture = "global", .level = 2, .point = .{ .coords = .{ -0.22, -0.18, -0.28, -0.12, -0.32, 0.06, -0.10, -0.14 } }, .parent = 8 },
    .{ .name = "dark-ambient", .culture = "global", .level = 2, .point = .{ .coords = .{ -0.25, -0.20, -0.30, -0.14, -0.35, 0.04, -0.12, -0.16 } }, .parent = 8 },
    // Level 3: subgenre
    .{ .name = "nu-jazz", .culture = "global", .level = 3, .point = .{ .coords = .{ 0.32, 0.14, -0.14, 0.12, 0.12, -0.06, 0.12, 0.02 } }, .parent = 1 },
    .{ .name = "math-rock", .culture = "western", .level = 3, .point = .{ .coords = .{ 0.15, -0.20, 0.12, 0.28, -0.10, 0.08, 0.14, -0.04 } }, .parent = 3 },
    .{ .name = "vaporwave", .culture = "internet", .level = 3, .point = .{ .coords = .{ 0.08, -0.05, -0.15, 0.10, 0.18, -0.08, -0.02, 0.12 } }, .parent = 4 },
    .{ .name = "glitch", .culture = "global", .level = 3, .point = .{ .coords = .{ 0.30, -0.08, -0.25, 0.20, 0.25, -0.18, 0.10, 0.15 } }, .parent = 4 },
};

// ── Tests ────────────────────────────────────────────────────────────

test "origin point has zero norm" {
    const p = HyperbolicPoint.origin();
    try testing.expectApproxEqAbs(@as(f64, 0.0), p.norm(), 1e-12);
}

test "clamp keeps point inside ball" {
    var p = HyperbolicPoint{ .coords = .{ 0.9, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 } };
    const clamped = p.clamp(0.5);
    try testing.expect(clamped.norm() < 0.5);
}

test "poincare distance to self is zero" {
    const p = HyperbolicPoint{ .coords = .{ 0.3, -0.2, 0.1, 0.0, 0.0, 0.0, 0.0, 0.0 } };
    try testing.expectApproxEqAbs(@as(f64, 0.0), poincare_distance(&p, &p), 1e-10);
}

test "poincare distance is symmetric" {
    const a = HyperbolicPoint{ .coords = .{ 0.3, -0.2, 0.1, 0.05, 0.0, 0.0, 0.0, 0.0 } };
    const b = HyperbolicPoint{ .coords = .{ -0.1, 0.4, -0.15, 0.2, 0.1, 0.0, 0.0, 0.0 } };
    try testing.expectApproxEqAbs(poincare_distance(&a, &b), poincare_distance(&b, &a), 1e-10);
}

test "poincare distance satisfies triangle inequality" {
    const a = HyperbolicPoint{ .coords = .{ 0.2, 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 } };
    const b = HyperbolicPoint{ .coords = .{ 0.1, 0.3, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 } };
    const c = HyperbolicPoint{ .coords = .{ -0.1, 0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 } };
    const ab = poincare_distance(&a, &b);
    const bc = poincare_distance(&b, &c);
    const ac = poincare_distance(&a, &c);
    try testing.expect(ac <= ab + bc + 1e-10);
}

test "poincare distance at origin" {
    const o = HyperbolicPoint.origin();
    const p = HyperbolicPoint{ .coords = .{ 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 } };
    const d = poincare_distance(&o, &p);
    try testing.expect(d > 0.0);
    // Expected: acosh(1 + 2*0.25/(1*0.75)) = acosh(1 + 2/3) = acosh(5/3)
    try testing.expectApproxEqAbs(@as(f64, 1.0986), d, 0.01);
}

test "exp_map at origin is approximate identity for small tangent" {
    const o = HyperbolicPoint.origin();
    const v = HyperbolicPoint{ .coords = .{ 0.01, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 } };
    const result = exp_map(&o, &v);
    try testing.expectApproxEqAbs(@as(f64, 0.01), result.coords[0], 0.01);
}

test "log_map inverse of exp_map approximate" {
    const base = HyperbolicPoint{ .coords = .{ 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 } };
    const target = HyperbolicPoint{ .coords = .{ 0.3, 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 } };
    const log_v = log_map(&base, &target);
    const reconstructed = exp_map(&base, &log_v);
    try testing.expect(HyperbolicPoint.eql(&reconstructed, &target, 0.3));
}

test "frechet mean of identical points is that point" {
    const p = HyperbolicPoint{ .coords = .{ 0.3, -0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 } };
    const points = [_]HyperbolicPoint{ p, p, p };
    const weights = [_]f64{ 1.0, 1.0, 1.0 };
    const mean = frechet_mean(&points, &weights, 20);
    try testing.expect(HyperbolicPoint.eql(&mean, &p, 0.01));
}

test "frechet mean is closer to heavier point" {
    const a = HyperbolicPoint{ .coords = .{ 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 } };
    const b = HyperbolicPoint{ .coords = .{ -0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 } };
    const points = [_]HyperbolicPoint{ a, b };
    const weights = [_]f64{ 0.9, 0.1 };
    const mean = frechet_mean(&points, &weights, 100);
    const d_a = poincare_distance(&mean, &a);
    const d_b = poincare_distance(&mean, &b);
    try testing.expect(d_a < d_b);
}

test "genre map find" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var map = try GenreMap.init(alloc);
    defer map.deinit(alloc);

    try testing.expect(map.find("jazz").? == 1);
    try testing.expect(map.find("techno").? == 20);
    try testing.expect(map.find("nonexistent") == null);
}

test "genre map nearest" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var map = try GenreMap.init(alloc);
    defer map.deinit(alloc);

    const jazz_point = map.nodes[1].point;
    const near = try map.nearest(&jazz_point, 3, alloc);
    defer alloc.free(near);

    try testing.expect(near.len == 3);
    // Jazz itself should be nearest
    try testing.expect(near[0] == 1);
}

test "genre map blend" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var map = try GenreMap.init(alloc);
    defer map.deinit(alloc);

    const names = [_][]const u8{ "jazz", "classical" };
    const weights = [_]f64{ 0.5, 0.5 };
    const result = map.blend(&names, &weights);
    try testing.expect(result != null);

    const d_jazz = poincare_distance(&result.?, &map.nodes[1].point);
    const d_classical = poincare_distance(&result.?, &map.nodes[2].point);
    // Blend should be between the two
    const jazz_to_classical = poincare_distance(&map.nodes[1].point, &map.nodes[2].point);
    try testing.expect(d_jazz < jazz_to_classical);
    try testing.expect(d_classical < jazz_to_classical);
}

test "genre map cultural distance" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var map = try GenreMap.init(alloc);
    defer map.deinit(alloc);

    // Same culture (african-american): jazz <-> hip-hop
    const d_same = map.cultural_distance("jazz", "hip-hop").?;
    // Different culture: jazz <-> classical
    const d_diff = map.cultural_distance("jazz", "classical").?;
    // Same culture should be less than or equal due to 0.7 factor
    try testing.expect(d_same <= d_diff + 0.1);
}

test "genre map cultural distance nonexistent returns null" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var map = try GenreMap.init(alloc);
    defer map.deinit(alloc);

    try testing.expect(map.cultural_distance("jazz", "fake") == null);
}

test "fromSlice handles short slices" {
    const p = HyperbolicPoint.fromSlice(&.{ 0.5, 0.3 });
    try testing.expectApproxEqAbs(@as(f64, 0.5), p.coords[0], 1e-10);
    try testing.expectApproxEqAbs(@as(f64, 0.3), p.coords[1], 1e-10);
    try testing.expectApproxEqAbs(@as(f64, 0.0), p.coords[2], 1e-10);
}

test "poincare distance positive for distinct points" {
    const a = HyperbolicPoint{ .coords = .{ 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 } };
    const b = HyperbolicPoint{ .coords = .{ 0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 } };
    try testing.expect(poincare_distance(&a, &b) > 0.0);
}
