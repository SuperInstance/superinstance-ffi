//! Musical Cohomology — compute H⁰ and H¹ for chord progressions.
//!
//! Ported from fm-research/musical_cohomology.py — chord complex, H0, H1,
//! classification, and Roman numeral parsing.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub const Chord = u8;

pub const ProgressionClass = enum {
    simple, // H1 = 0 or 1
    moderate, // H1 = 2
    complex, // H1 = 3
    highly_chromatic, // H1 >= 4
};

pub const CohomologyResult = struct {
    h0: usize,
    h1: usize,
    emergence_detected: bool,
    n_vertices: usize,
    n_edges: usize,
};

pub const MAJOR_SCALE = [_]u8{ 0, 2, 4, 5, 7, 9, 11 };
pub const MINOR_SCALE = [_]u8{ 0, 2, 3, 5, 7, 8, 10 };

// ── Chord Complex ────────────────────────────────────────────────────

pub const ChordComplex = struct {
    /// The full chord sequence (as provided, may have repeats)
    sequence: std.ArrayList(Chord),
    /// Set of unique chords (vertices)
    vertices: std.AutoHashMap(Chord, void),
    /// Set of unique undirected edges (stored as sorted pair)
    edges: std.ArrayList([2]Chord),
    /// Adjacency list: chord -> set of neighbor chords
    adj: std.AutoHashMap(Chord, std.AutoHashMap(Chord, void)),
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .sequence = std.ArrayList(Chord).init(allocator),
            .vertices = std.AutoHashMap(Chord, void).init(allocator),
            .edges = std.ArrayList([2]Chord).init(allocator),
            .adj = std.AutoHashMap(Chord, std.AutoHashMap(Chord, void)).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.adj.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.adj.deinit();
        self.vertices.deinit();
        self.sequence.deinit();
        self.edges.deinit();
    }

    pub fn addChord(self: *Self, root: Chord) !void {
        const pc = root % 12;
        try self.vertices.put(pc, {});

        if (self.sequence.items.len > 0) {
            const prev = self.sequence.items[self.sequence.items.len - 1];
            if (pc != prev) {
                // Check if edge already exists
                const lo = @min(prev, pc);
                const hi = @max(prev, pc);
                const edge = [2]Chord{ lo, hi };
                var exists = false;
                for (self.edges.items) |e| {
                    if (e[0] == edge[0] and e[1] == edge[1]) {
                        exists = true;
                        break;
                    }
                }
                if (!exists) {
                    try self.edges.append(edge);
                }
                // Update adjacency (always, even if edge already tracked)
                var adj_a = try self.adj.getOrPut(prev);
                if (!adj_a.found_existing) adj_a.value_ptr.* = std.AutoHashMap(Chord, void).init(self.allocator);
                try adj_a.value_ptr.put(pc, {});
                var adj_b = try self.adj.getOrPut(pc);
                if (!adj_b.found_existing) adj_b.value_ptr.* = std.AutoHashMap(Chord, void).init(self.allocator);
                try adj_b.value_ptr.put(prev, {});
            }
        }
        try self.sequence.append(pc);
    }

    pub fn fromRoots(allocator: Allocator, roots: []const Chord) !Self {
        var complex = Self.init(allocator);
        for (roots) |r| {
            try complex.addChord(r);
        }
        return complex;
    }

    pub fn nVertices(self: *const Self) usize {
        return self.vertices.count();
    }

    pub fn nEdges(self: *const Self) usize {
        return self.edges.items.len;
    }

    pub fn computeH0(self: *Self) usize {
        if (self.vertices.count() == 0) return 0;
        var visited = std.AutoHashMap(Chord, void).init(self.allocator);
        defer visited.deinit();
        var components: usize = 0;

        var vit = self.vertices.iterator();
        while (vit.next()) |entry| {
            const start = entry.key_ptr.*;
            if (visited.contains(start)) continue;
            components += 1;
            // BFS
            var queue = std.ArrayList(Chord).init(self.allocator);
            defer queue.deinit();
            queue.append(start) catch continue;
            while (queue.items.len > 0) {
                const node = queue.orderedRemove(0);
                if (visited.contains(node)) continue;
                visited.put(node, {}) catch continue;
                if (self.adj.get(node)) |neighbors| {
                    var nit = neighbors.iterator();
                    while (nit.next()) |ne| {
                        if (!visited.contains(ne.key_ptr.*)) {
                            queue.append(ne.key_ptr.*) catch {};
                        }
                    }
                }
            }
        }
        return components;
    }

    pub fn computeH1(self: *Self) usize {
        const e = self.nEdges();
        const v = self.nVertices();
        const h0 = self.computeH0();
        const result = e + h0;
        if (result >= v) return result - v;
        return 0;
    }

    pub fn classify(self: *Self) ProgressionClass {
        const h1 = self.computeH1();
        return switch (h1) {
            0, 1 => .simple,
            2 => .moderate,
            3 => .complex,
            else => .highly_chromatic,
        };
    }

    pub fn analyze(self: *Self) CohomologyResult {
        const h0 = self.computeH0();
        const h1 = self.computeH1();
        return CohomologyResult{
            .h0 = h0,
            .h1 = h1,
            .emergence_detected = h1 > 0,
            .n_vertices = self.nVertices(),
            .n_edges = self.nEdges(),
        };
    }
};

// ── Roman numeral parser ─────────────────────────────────────────────

fn romanDegree(numeral: []const u8) ?usize {
    const candidates = [_]struct { []const u8, usize }{
        .{ "III", 2 }, .{ "VII", 6 }, .{ "II", 1 }, .{ "IV", 3 },
        .{ "VI", 5 },  .{ "I", 0 },   .{ "iii", 2 }, .{ "vii", 6 },
        .{ "ii", 1 },  .{ "iv", 3 },  .{ "vi", 5 },  .{ "i", 0 },
        .{ "V", 4 },   .{ "v", 4 },
    };
    for (candidates) |cand| {
        if (std.mem.startsWith(u8, numeral, cand[0])) return cand[1];
    }
    return null;
}

pub fn parseRomanNumeral(text: []const u8) ?Chord {
    return parseRomanInKey(text, 0, true);
}

pub fn parseRomanInKey(text: []const u8, key_tonic: Chord, major: bool) ?Chord {
    var buf = text;
    var flat_count: u8 = 0;
    var sharp_count: u8 = 0;

    while (buf.len > 0 and (buf[0] == 'b' or buf[0] == '#')) {
        if (buf[0] == 'b') flat_count += 1;
        if (buf[0] == '#') sharp_count += 1;
        buf = buf[1..];
    }

    const degree = romanDegree(buf) orelse return null;
    const scale = if (major) &MAJOR_SCALE else &MINOR_SCALE;
    var pc: Chord = (key_tonic + scale[degree]) % 12;
    pc = (pc -% flat_count +% sharp_count) % 12;
    return pc;
}

// ── Famous progressions ──────────────────────────────────────────────

pub fn pachelbelCanon(allocator: Allocator) !ChordComplex {
    const numerals = [_][]const u8{ "I", "V", "vi", "iii", "IV", "I", "IV", "V" };
    return fromRomanNumerals(allocator, &numerals, 2, true);
}

pub fn blues12Bar(allocator: Allocator) !ChordComplex {
    return ChordComplex.fromRoots(allocator, &[_]Chord{ 0, 0, 0, 0, 5, 5, 0, 0, 7, 5, 0, 7 });
}

pub fn giantSteps(allocator: Allocator) !ChordComplex {
    return ChordComplex.fromRoots(allocator, &[_]Chord{ 11, 2, 7, 10, 3, 6, 11, 3, 9, 2, 7, 10, 3, 6, 11 });
}

pub fn axisProgression(allocator: Allocator) !ChordComplex {
    const numerals = [_][]const u8{ "I", "V", "vi", "IV" };
    return fromRomanNumerals(allocator, &numerals, 0, true);
}

pub fn rhythmChanges(allocator: Allocator) !ChordComplex {
    const numerals = [_][]const u8{ "I", "vi", "ii", "V", "I", "vi", "ii", "V", "iii", "VI", "ii", "V", "I" };
    return fromRomanNumerals(allocator, &numerals, 0, true);
}

pub fn fromRomanNumerals(allocator: Allocator, numerals: []const []const u8, key_tonic: Chord, major: bool) !ChordComplex {
    var complex = ChordComplex.init(allocator);
    for (numerals) |n| {
        const pc = parseRomanInKey(n, key_tonic, major) orelse return error.InvalidNumeral;
        try complex.addChord(pc);
    }
    return complex;
}

// ══════════════════════════════════════════════════════════════════════
// Tests
// ══════════════════════════════════════════════════════════════════════

test "ChordComplex: single chord H0=1 H1=0" {
    const allocator = testing.allocator;
    var c = try ChordComplex.fromRoots(allocator, &[_]Chord{0});
    defer c.deinit();
    try testing.expectEqual(@as(usize, 1), c.computeH0());
    try testing.expectEqual(@as(usize, 0), c.computeH1());
}

test "ChordComplex: two chords H0=1 H1=0" {
    const allocator = testing.allocator;
    var c = try ChordComplex.fromRoots(allocator, &[_]Chord{ 0, 7 });
    defer c.deinit();
    try testing.expectEqual(@as(usize, 1), c.computeH0());
    try testing.expectEqual(@as(usize, 0), c.computeH1());
}

test "ChordComplex: triangle H1=1" {
    const allocator = testing.allocator;
    // C(0) -> F(5) -> G(7) -> C(0)
    // Edges: {0,5}, {5,7}, {0,7} = 3 edges, 3 vertices
    // H1 = 3 - 3 + 1 = 1
    var c = try ChordComplex.fromRoots(allocator, &[_]Chord{ 0, 5, 7, 0 });
    defer c.deinit();
    try testing.expectEqual(@as(usize, 3), c.nVertices());
    try testing.expectEqual(@as(usize, 3), c.nEdges());
    try testing.expectEqual(@as(usize, 1), c.computeH0());
    try testing.expectEqual(@as(usize, 1), c.computeH1());
}

test "ChordComplex: repeated chord no new edge" {
    const allocator = testing.allocator;
    var c = try ChordComplex.fromRoots(allocator, &[_]Chord{ 0, 0, 0 });
    defer c.deinit();
    try testing.expectEqual(@as(usize, 1), c.nVertices());
    try testing.expectEqual(@as(usize, 0), c.nEdges());
    try testing.expectEqual(@as(usize, 0), c.computeH1());
}

test "ChordComplex: blues H0=1" {
    const allocator = testing.allocator;
    var c = try blues12Bar(allocator);
    defer c.deinit();
    try testing.expectEqual(@as(usize, 1), c.computeH0());
}

test "ChordComplex: blues H1=1" {
    const allocator = testing.allocator;
    // 12-bar blues: 0,0,0,0,5,5,0,0,7,5,0,7
    // Unique: 0, 5, 7 = 3 vertices
    // Edges: {0,5}, {0,7}, {5,7} = 3 edges
    // H1 = 3 - 3 + 1 = 1
    var c = try blues12Bar(allocator);
    defer c.deinit();
    try testing.expectEqual(@as(usize, 3), c.nEdges());
    try testing.expectEqual(@as(usize, 1), c.computeH1());
}

test "ChordComplex: blues 3 distinct roots" {
    const allocator = testing.allocator;
    var c = try blues12Bar(allocator);
    defer c.deinit();
    try testing.expectEqual(@as(usize, 3), c.nVertices());
}

test "ChordComplex: Pachelbel H0=1" {
    const allocator = testing.allocator;
    var c = try pachelbelCanon(allocator);
    defer c.deinit();
    try testing.expectEqual(@as(usize, 1), c.computeH0());
}

test "ChordComplex: Pachelbel H1>=1" {
    const allocator = testing.allocator;
    var c = try pachelbelCanon(allocator);
    defer c.deinit();
    try testing.expect(c.computeH1() >= 1);
}

test "ChordComplex: Pachelbel emergence" {
    const allocator = testing.allocator;
    var c = try pachelbelCanon(allocator);
    defer c.deinit();
    const result = c.analyze();
    try testing.expect(result.emergence_detected);
}

test "ChordComplex: Pachelbel 5 vertices" {
    const allocator = testing.allocator;
    var c = try pachelbelCanon(allocator);
    defer c.deinit();
    try testing.expectEqual(@as(usize, 5), c.nVertices());
}

test "ChordComplex: Giant Steps H1>=1" {
    const allocator = testing.allocator;
    var c = try giantSteps(allocator);
    defer c.deinit();
    try testing.expect(c.computeH1() >= 1);
}

test "ChordComplex: Giant Steps emergence" {
    const allocator = testing.allocator;
    var c = try giantSteps(allocator);
    defer c.deinit();
    try testing.expect(c.analyze().emergence_detected);
}

test "ChordComplex: Rhythm changes H0=1" {
    const allocator = testing.allocator;
    var c = try rhythmChanges(allocator);
    defer c.deinit();
    try testing.expectEqual(@as(usize, 1), c.computeH0());
}

test "ChordComplex: Rhythm changes H1>=1" {
    const allocator = testing.allocator;
    var c = try rhythmChanges(allocator);
    defer c.deinit();
    try testing.expect(c.computeH1() >= 1);
}

test "classify: blues is simple" {
    const allocator = testing.allocator;
    var c = try blues12Bar(allocator);
    defer c.deinit();
    try testing.expectEqual(ProgressionClass.simple, c.classify());
}

test "classify: axis progression is simple" {
    const allocator = testing.allocator;
    var c = try axisProgression(allocator);
    defer c.deinit();
    try testing.expectEqual(ProgressionClass.simple, c.classify());
}

test "Roman numeral: parse I in C" {
    const pc = parseRomanNumeral("I");
    try testing.expect(pc != null);
    try testing.expectEqual(@as(Chord, 0), pc.?);
}

test "Roman numeral: parse V in C" {
    const pc = parseRomanInKey("V", 0, true);
    try testing.expect(pc != null);
    try testing.expectEqual(@as(Chord, 7), pc.?);
}

test "Roman numeral: parse vi in C" {
    const pc = parseRomanInKey("vi", 0, true);
    try testing.expect(pc != null);
    try testing.expectEqual(@as(Chord, 9), pc.?);
}

test "Roman numeral: parse bVI in C" {
    const pc = parseRomanInKey("bVI", 0, true);
    try testing.expect(pc != null);
    try testing.expectEqual(@as(Chord, 8), pc.?);
}

test "Roman numeral: invalid returns null" {
    try testing.expect(parseRomanNumeral("xyz") == null);
}

test "ChordComplex: theorem1 single key H0=1" {
    const allocator = testing.allocator;
    var blues = try blues12Bar(allocator);
    defer blues.deinit();
    var pachelbel = try pachelbelCanon(allocator);
    defer pachelbel.deinit();
    try testing.expectEqual(@as(usize, 1), blues.computeH0());
    try testing.expectEqual(@as(usize, 1), pachelbel.computeH0());
}

test "ChordComplex: theorem5 emergence condition" {
    const allocator = testing.allocator;
    var c = try blues12Bar(allocator);
    defer c.deinit();
    const result = c.analyze();
    if (result.h1 > 0) {
        try testing.expect(result.n_edges > result.n_vertices - 1);
    }
}

test "ChordComplex: four-chord loop I-IV-V-I" {
    const allocator = testing.allocator;
    // C(0)->F(5)->G(7)->C(0): same as triangle test
    var c = try ChordComplex.fromRoots(allocator, &[_]Chord{ 0, 5, 7, 0 });
    defer c.deinit();
    try testing.expectEqual(@as(usize, 1), c.computeH0());
    try testing.expectEqual(@as(usize, 1), c.computeH1());
}
