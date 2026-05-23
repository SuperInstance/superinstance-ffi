//! world_music.zig — World music scales, tuning systems, ornaments, rhythms,
//! spline wavetable synth, and core constraint primitives.
//!
//! Ported from the C single-header library (world_music.h, spline_synth.h,
//! superinstance-ffi.h). Uses Zig idioms: comptime constants, proper error
//! handling, ArrayList for dynamic arrays, no external dependencies.

const std = @import("std");
const math = std.math;
const mem = std.mem;
const testing = std.testing;
const assert = std.debug.assert;
const Allocator = mem.Allocator;

// ══════════════════════════════════════════════════════════════════════
// Constants
// ══════════════════════════════════════════════════════════════════════

pub const PHI = 1.618033988749895;
pub const INV_PHI = 0.618033988749895;
pub const PI = 3.14159265358979323846;
pub const TWO_PI = 6.283185307179586;
pub const MAX_NOTES: usize = 12;
pub const MAX_HITS: usize = 32;
pub const MAX_SHRUTI: usize = 22;
pub const NUM_SCALES: usize = 36;
pub const NUM_RHYTHMS: usize = 26;

// ══════════════════════════════════════════════════════════════════════
// Scales — 36 world scales
// ══════════════════════════════════════════════════════════════════════

pub const WorldScale = struct {
    name: [:0]const u8,
    culture: [:0]const u8,
    notes: [MAX_NOTES]i32,
    note_count: usize,
    vadi: f64,
    samvadi: f64,
    rasa: ?[:0]const u8,
};

// Helper: build a scale with default-padded note array
fn Scale(comptime nc: usize, comptime n: [nc]i32) [MAX_NOTES]i32 {
    var arr: [MAX_NOTES]i32 = [_]i32{0} ** MAX_NOTES;
    for (n, 0..) |v, i| arr[i] = v;
    return arr;
}

pub const SCALES = blk: {
    @setEvalBranchQuota(10000);
    break :blk [NUM_SCALES]WorldScale{
        // Indian Ragas (10)
        .{ .name = "bhairavi", .culture = "indian", .notes = Scale(7, .{ 0, 1, 3, 5, 7, 8, 10 }), .note_count = 7, .vadi = 1, .samvadi = 5, .rasa = "devotional" },
        .{ .name = "yaman", .culture = "indian", .notes = Scale(7, .{ 0, 2, 4, 6, 7, 9, 11 }), .note_count = 7, .vadi = 0, .samvadi = 4, .rasa = "romantic" },
        .{ .name = "darbari", .culture = "indian", .notes = Scale(7, .{ 0, 2, 3, 5, 7, 8, 10 }), .note_count = 7, .vadi = 3, .samvadi = 7, .rasa = "solemn" },
        .{ .name = "malkauns", .culture = "indian", .notes = Scale(6, .{ 0, 2, 4, 6, 8, 10 }), .note_count = 6, .vadi = 2, .samvadi = 6, .rasa = "meditative" },
        .{ .name = "bageshri", .culture = "indian", .notes = Scale(7, .{ 0, 2, 3, 5, 7, 9, 10 }), .note_count = 7, .vadi = 2, .samvadi = 7, .rasa = "longing" },
        .{ .name = "todi", .culture = "indian", .notes = Scale(7, .{ 0, 1, 3, 5, 7, 8, 11 }), .note_count = 7, .vadi = 3, .samvadi = 7, .rasa = "pathos" },
        .{ .name = "bhairav", .culture = "indian", .notes = Scale(7, .{ 0, 1, 4, 5, 7, 8, 11 }), .note_count = 7, .vadi = 4, .samvadi = 8, .rasa = "solemn" },
        .{ .name = "kafi", .culture = "indian", .notes = Scale(7, .{ 0, 2, 3, 5, 7, 9, 10 }), .note_count = 7, .vadi = 3, .samvadi = 7, .rasa = "playful" },
        .{ .name = "bilawal", .culture = "indian", .notes = Scale(7, .{ 0, 2, 4, 5, 7, 9, 11 }), .note_count = 7, .vadi = 4, .samvadi = 0, .rasa = "joyful" },
        .{ .name = "asavari", .culture = "indian", .notes = Scale(7, .{ 0, 2, 3, 5, 7, 8, 10 }), .note_count = 7, .vadi = 3, .samvadi = 7, .rasa = "melancholy" },

        // Arabic / Turkish Maqamat (10)
        .{ .name = "rast", .culture = "arabic", .notes = Scale(7, .{ 0, 2, 4, 5, 7, 9, 11 }), .note_count = 7, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "bayati", .culture = "arabic", .notes = Scale(7, .{ 0, 2, 4, 5, 7, 9, 10 }), .note_count = 7, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "hijaz", .culture = "arabic", .notes = Scale(7, .{ 0, 1, 4, 5, 7, 8, 11 }), .note_count = 7, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "sikah", .culture = "arabic", .notes = Scale(7, .{ 0, 2, 4, 5, 7, 9, 11 }), .note_count = 7, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "nahawand", .culture = "arabic", .notes = Scale(7, .{ 0, 2, 3, 5, 7, 8, 11 }), .note_count = 7, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "kurd", .culture = "arabic", .notes = Scale(7, .{ 0, 1, 3, 5, 7, 8, 10 }), .note_count = 7, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "ajam", .culture = "arabic", .notes = Scale(7, .{ 0, 2, 4, 5, 7, 9, 11 }), .note_count = 7, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "saba", .culture = "arabic", .notes = Scale(7, .{ 0, 1, 3, 4, 6, 7, 10 }), .note_count = 7, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "huzam", .culture = "arabic", .notes = Scale(7, .{ 0, 2, 4, 5, 7, 9, 10 }), .note_count = 7, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "nakriz", .culture = "arabic", .notes = Scale(7, .{ 0, 2, 3, 5, 7, 8, 11 }), .note_count = 7, .vadi = -1, .samvadi = -1, .rasa = null },

        // East Asian Pentatonic (10)
        .{ .name = "in_scale", .culture = "japanese", .notes = Scale(5, .{ 0, 2, 3, 7, 8 }), .note_count = 5, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "yo_scale", .culture = "japanese", .notes = Scale(5, .{ 0, 2, 5, 7, 9 }), .note_count = 5, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "hirajoshi", .culture = "japanese", .notes = Scale(5, .{ 0, 2, 3, 7, 8 }), .note_count = 5, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "kumoi", .culture = "japanese", .notes = Scale(5, .{ 0, 2, 3, 7, 9 }), .note_count = 5, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "gong_mode", .culture = "chinese", .notes = Scale(5, .{ 0, 2, 4, 7, 9 }), .note_count = 5, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "shang_mode", .culture = "chinese", .notes = Scale(5, .{ 0, 2, 4, 7, 9 }), .note_count = 5, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "jiao_mode", .culture = "chinese", .notes = Scale(5, .{ 0, 2, 5, 7, 10 }), .note_count = 5, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "zhi_mode", .culture = "chinese", .notes = Scale(5, .{ 0, 2, 5, 7, 10 }), .note_count = 5, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "yu_mode", .culture = "chinese", .notes = Scale(5, .{ 0, 3, 5, 7, 10 }), .note_count = 5, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "pentatonic_major", .culture = "east_asian", .notes = Scale(5, .{ 0, 2, 4, 7, 9 }), .note_count = 5, .vadi = -1, .samvadi = -1, .rasa = null },

        // African Scales (6)
        .{ .name = "ewe_standard", .culture = "ewe", .notes = Scale(7, .{ 0, 2, 4, 5, 7, 9, 11 }), .note_count = 7, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "pentatonic_african", .culture = "african", .notes = Scale(5, .{ 0, 2, 3, 7, 8 }), .note_count = 5, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "zimbabwe_mbira", .culture = "shona", .notes = Scale(6, .{ 0, 3, 5, 7, 8, 10 }), .note_count = 6, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "amadinda_scale", .culture = "buganda", .notes = Scale(6, .{ 0, 2, 4, 5, 7, 9 }), .note_count = 6, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "manden_scale", .culture = "manden", .notes = Scale(7, .{ 0, 2, 4, 6, 7, 9, 11 }), .note_count = 7, .vadi = -1, .samvadi = -1, .rasa = null },
        .{ .name = "tigre_scale", .culture = "tigre", .notes = Scale(7, .{ 0, 1, 3, 5, 7, 8, 10 }), .note_count = 7, .vadi = -1, .samvadi = -1, .rasa = null },
    };
};

// Named scale constants
pub const RAGA_BHAIRAVI = &SCALES[0];
pub const RAGA_YAMAN = &SCALES[1];
pub const RAGA_DARBARI = &SCALES[2];
pub const RAGA_MALKAUNS = &SCALES[3];
pub const RAGA_BAGESHRI = &SCALES[4];
pub const RAGA_TODI = &SCALES[5];
pub const RAGA_BHAIRAV = &SCALES[6];
pub const RAGA_KAFI = &SCALES[7];
pub const RAGA_BILAWAL = &SCALES[8];
pub const RAGA_ASAVARI = &SCALES[9];
pub const MAQAM_RAST = &SCALES[10];
pub const MAQAM_BAYATI = &SCALES[11];
pub const MAQAM_HIJAZ = &SCALES[12];
pub const MAQAM_SIKAH = &SCALES[13];
pub const MAQAM_NAHAWAND = &SCALES[14];
pub const MAQAM_KURD = &SCALES[15];
pub const MAQAM_AJAM = &SCALES[16];
pub const MAQAM_SABA = &SCALES[17];
pub const MAQAM_HUZAM = &SCALES[18];
pub const MAQAM_NAKRIZ = &SCALES[19];
pub const IN_SCALE = &SCALES[20];
pub const YO_SCALE = &SCALES[21];

pub fn getScale(name: []const u8) ?*const WorldScale {
    for (&SCALES) |*s| {
        if (strieq(name, s.name)) return s;
    }
    return null;
}

pub fn scalesByCulture(culture: []const u8, out: []?*const WorldScale) usize {
    var n: usize = 0;
    for (&SCALES) |*s| {
        if (n >= out.len) break;
        if (strieq(culture, s.culture)) {
            out[n] = s;
            n += 1;
        }
    }
    return n;
}

pub fn scaleToMidi(name: []const u8, root: i32, octave_range: i32, out: []i32) usize {
    const s = getScale(name) orelse return 0;
    var count: usize = 0;
    for (0..@intCast(octave_range)) |oct| {
        for (0..s.note_count) |n| {
            const midi: i32 = root + s.notes[n] + @as(i32, @intCast(oct)) * 12;
            if (midi < 0 or midi > 127) continue;
            if (count >= out.len) break;
            // deduplicate
            var dup = false;
            for (out[0..count]) |existing| {
                if (existing == midi) {
                    dup = true;
                    break;
                }
            }
            if (!dup) {
                out[count] = midi;
                count += 1;
            }
        }
    }
    // sort
    std.sort.pdq(i32, out[0..count], {}, comptime std.sort.asc(i32));
    return count;
}

// ══════════════════════════════════════════════════════════════════════
// Tuning Systems — 7 systems
// ══════════════════════════════════════════════════════════════════════

pub const TuningSystem = struct {
    name: [:0]const u8,
    divisions: usize,
    generator: *const fn (i32) f64,
};

pub fn equalTemperamentCents(degree: i32) f64 {
    return @as(f64, @floatFromInt(degree)) * (1200.0 / 12.0);
}

pub fn justIntonationCents(degree: i32) f64 {
    const ratios = [12]f64{
        1, 16.0 / 15.0, 9.0 / 8.0, 6.0 / 5.0, 5.0 / 4.0, 4.0 / 3.0,
        45.0 / 32.0, 3.0 / 2.0, 8.0 / 5.0, 5.0 / 3.0, 9.0 / 5.0, 15.0 / 8.0,
    };
    if (degree < 0 or degree >= 12) return 0.0;
    return ratioToCents(ratios[@intCast(degree)]);
}

pub fn shruti22Cents(degree: i32) f64 {
    const ratios = [22]f64{
        1, 256.0 / 243.0, 16.0 / 15.0, 10.0 / 9.0, 9.0 / 8.0, 32.0 / 27.0,
        6.0 / 5.0, 5.0 / 4.0, 81.0 / 64.0, 4.0 / 3.0, 27.0 / 20.0, 45.0 / 32.0,
        729.0 / 512.0, 3.0 / 2.0, 128.0 / 81.0, 8.0 / 5.0, 5.0 / 3.0, 27.0 / 16.0,
        16.0 / 9.0, 9.0 / 5.0, 15.0 / 8.0, 243.0 / 128.0,
    };
    if (degree < 0 or degree >= 22) return 0.0;
    return ratioToCents(ratios[@intCast(degree)]);
}

pub fn quarterTone24Cents(degree: i32) f64 {
    return @as(f64, @floatFromInt(degree)) * 50.0;
}

pub fn pentatonic5Cents(degree: i32) f64 {
    return @as(f64, @floatFromInt(degree)) * 240.0;
}

// Meantone & Pythagorean: build at comptime via cycle of fifths
pub fn meantoneCents(degree: i32) f64 {
    @setEvalBranchQuota(3000);
    const notes = comptime blk: {
        var arr: [12]f64 = undefined;
        const fifth = 1200.0 * @log2(math.pow(f64, 5.0, 0.25));
        var acc: f64 = 0;
        arr[0] = 0;
        for (1..12) |i| {
            acc += fifth;
            acc = @mod(acc, 1200.0);
            arr[i] = acc;
        }
        // sort
        const S = struct {
            fn lessThan(_: void, a: f64, b: f64) bool {
                return a < b;
            }
        };
        std.sort.pdq(f64, &arr, {}, S.lessThan);
        break :blk arr;
    };
    if (degree < 0 or degree >= 12) return 0.0;
    return notes[@intCast(degree)];
}

pub fn pythagoreanCents(degree: i32) f64 {
    @setEvalBranchQuota(3000);
    const notes = comptime blk: {
        var arr: [12]f64 = undefined;
        const fifth = 1200.0 * @log2(3.0 / 2.0);
        var acc: f64 = 0;
        arr[0] = 0;
        for (1..12) |i| {
            acc += fifth;
            acc = @mod(acc, 1200.0);
            arr[i] = acc;
        }
        const S = struct {
            fn lessThan(_: void, a: f64, b: f64) bool {
                return a < b;
            }
        };
        std.sort.pdq(f64, &arr, {}, S.lessThan);
        break :blk arr;
    };
    if (degree < 0 or degree >= 12) return 0.0;
    return notes[@intCast(degree)];
}

pub const TUNING_EQUAL_TEMPERAMENT = TuningSystem{ .name = "equal_temperament", .divisions = 12, .generator = equalTemperamentCents };
pub const TUNING_JUST_INTONATION = TuningSystem{ .name = "just_intonation", .divisions = 12, .generator = justIntonationCents };
pub const TUNING_SHRUTI_22 = TuningSystem{ .name = "shruti_22", .divisions = 22, .generator = shruti22Cents };
pub const TUNING_QUARTER_TONE_24 = TuningSystem{ .name = "quarter_tone_24", .divisions = 24, .generator = quarterTone24Cents };
pub const TUNING_PENTATONIC_5 = TuningSystem{ .name = "pentatonic_5", .divisions = 5, .generator = pentatonic5Cents };
pub const TUNING_MEANTONE = TuningSystem{ .name = "meantone", .divisions = 12, .generator = meantoneCents };
pub const TUNING_PYTHAGOREAN = TuningSystem{ .name = "pythagorean", .divisions = 12, .generator = pythagoreanCents };

pub fn tuningAllCents(sys: *const TuningSystem, out: []f64) usize {
    const n = @min(sys.divisions, out.len);
    for (0..n) |i| {
        out[i] = sys.generator(@intCast(i));
    }
    return n;
}

pub fn snapToTuning(note_cents: f64, sys: *const TuningSystem, epsilon: f64) f64 {
    var best_dist: f64 = 1e18;
    var best_val: f64 = 0.0;
    for (0..sys.divisions) |i| {
        const c = sys.generator(@intCast(i));
        const nc = @mod(note_cents, 1200.0);
        const cc = @mod(c, 1200.0);
        var diff = @abs(cc - nc);
        if (diff > 600.0) diff = 1200.0 - diff;
        if (diff < best_dist) {
            best_dist = diff;
            best_val = cc;
        }
    }
    if (epsilon > 0 and best_dist > epsilon) return note_cents;
    return best_val;
}

// ══════════════════════════════════════════════════════════════════════
// Ornaments — 4 types
// ══════════════════════════════════════════════════════════════════════

pub const CurveType = enum { exponential, logarithmic, linear };

pub fn meend(start: f64, end: f64, steps: usize, curve: CurveType, out: []f64) void {
    if (steps < 1) {
        out[0] = start;
        return;
    }
    for (0..steps + 1) |i| {
        const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(steps));
        const value = switch (curve) {
            .exponential => start + (end - start) * (t * t),
            .logarithmic => start + (end - start) * (1.0 - (1.0 - t) * (1.0 - t)),
            .linear => start + (end - start) * t,
        };
        out[i] = round4(value);
    }
}

pub fn gamak(center: f64, amplitude: f64, speed: f64, cycles: usize, out: []f64) usize {
    const total_points: usize = @intFromFloat(speed * @as(f64, @floatFromInt(cycles)) * 4.0);
    for (0..total_points + 1) |i| {
        const t = @as(f64, @floatFromInt(i)) / (if (total_points > 0) @as(f64, @floatFromInt(total_points)) else 1.0);
        const decay = 1.0 - t * 0.3;
        const val = center + amplitude * decay * @sin(2.0 * PI * speed * @as(f64, @floatFromInt(cycles)) * t);
        out[i] = round4(val);
    }
    return total_points + 1;
}

pub const BendDirection = enum { up, down };

pub fn quarterBend(note: f64, direction: BendDirection, cents: f64, steps: usize, out: []f64) usize {
    const semitones = cents / 100.0;
    const target = switch (direction) {
        .up => note + semitones,
        .down => note - semitones,
    };
    var idx: usize = 0;
    // smoothstep up
    for (0..steps + 1) |i| {
        const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(steps));
        const val = t * t * (3.0 - 2.0 * t);
        out[idx] = round4(note + (target - note) * val);
        idx += 1;
    }
    // hold
    for (0..4) |_| {
        out[idx] = round4(target);
        idx += 1;
    }
    // smoothstep down
    for (0..steps + 1) |i| {
        const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(steps));
        const val = t * t * (3.0 - 2.0 * t);
        out[idx] = round4(target + (note - target) * val);
        idx += 1;
    }
    return idx;
}

pub fn shakes(note: f64, speed: f64, amplitude: f64, out: []f64) usize {
    const points: usize = @intFromFloat(speed * 8.0);
    const n = @min(points, out.len);
    for (0..n) |i| {
        const t = @as(f64, @floatFromInt(i)) / (if (n > 1) @as(f64, @floatFromInt(n - 1)) else 1.0);
        const val = note + amplitude * @sin(2.0 * PI * speed * t);
        out[i] = round4(val);
    }
    return n;
}

// ══════════════════════════════════════════════════════════════════════
// Rhythms — 26 patterns
// ══════════════════════════════════════════════════════════════════════

pub const RhythmPattern = struct {
    name: [:0]const u8,
    culture: [:0]const u8,
    subdivisions: usize,
    hits: [MAX_HITS]bool,
    hit_count: usize,
};

fn Rhythm(comptime nc: usize, comptime h: [nc]usize) RhythmPattern {
    var hits: [MAX_HITS]bool = [_]bool{false} ** MAX_HITS;
    for (h) |idx| hits[idx] = true;
    return .{ .name = "", .culture = "", .subdivisions = 0, .hits = hits, .hit_count = nc };
}

pub const RHYTHMS = blk: {
    @setEvalBranchQuota(10000);
    break :blk [NUM_RHYTHMS]RhythmPattern{
        // Clave patterns (5)
        .{ .name = "son_2_3", .culture = "cuban", .subdivisions = 16, .hits = makeRhythmHits(5, .{ 0, 3, 6, 8, 11 }), .hit_count = 5 },
        .{ .name = "son_3_2", .culture = "cuban", .subdivisions = 16, .hits = makeRhythmHits(5, .{ 0, 3, 6, 10, 13 }), .hit_count = 5 },
        .{ .name = "rumba_2_3", .culture = "cuban", .subdivisions = 16, .hits = makeRhythmHits(5, .{ 0, 3, 6, 8, 12 }), .hit_count = 5 },
        .{ .name = "rumba_3_2", .culture = "cuban", .subdivisions = 16, .hits = makeRhythmHits(5, .{ 0, 4, 8, 10, 13 }), .hit_count = 5 },
        .{ .name = "bossa_nova", .culture = "brazilian", .subdivisions = 16, .hits = makeRhythmHits(6, .{ 0, 3, 6, 8, 11, 14 }), .hit_count = 6 },

        // Bell patterns (6)
        .{ .name = "agbadza", .culture = "ewe", .subdivisions = 12, .hits = makeRhythmHits(6, .{ 0, 3, 4, 6, 8, 10 }), .hit_count = 6 },
        .{ .name = "gahu", .culture = "ewe", .subdivisions = 12, .hits = makeRhythmHits(6, .{ 0, 2, 5, 6, 8, 10 }), .hit_count = 6 },
        .{ .name = "atsiagbekor", .culture = "ewe", .subdivisions = 12, .hits = makeRhythmHits(6, .{ 0, 2, 5, 6, 8, 11 }), .hit_count = 6 },
        .{ .name = "kinka", .culture = "ewe", .subdivisions = 12, .hits = makeRhythmHits(5, .{ 0, 3, 6, 8, 11 }), .hit_count = 5 },
        .{ .name = "yanvalou", .culture = "west_africa", .subdivisions = 16, .hits = makeRhythmHits(6, .{ 0, 3, 6, 9, 12, 15 }), .hit_count = 6 },
        .{ .name = "iren", .culture = "west_africa", .subdivisions = 16, .hits = makeRhythmHits(8, .{ 0, 2, 4, 6, 8, 10, 12, 14 }), .hit_count = 8 },

        // Indian talas (7)
        .{ .name = "teental", .culture = "indian", .subdivisions = 16, .hits = makeRhythmHits(4, .{ 0, 4, 8, 12 }), .hit_count = 4 },
        .{ .name = "jhap_tal", .culture = "indian", .subdivisions = 10, .hits = makeRhythmHits(4, .{ 0, 2, 5, 7 }), .hit_count = 4 },
        .{ .name = "rupak", .culture = "indian", .subdivisions = 7, .hits = makeRhythmHits(3, .{ 0, 3, 5 }), .hit_count = 3 },
        .{ .name = "ek_tal", .culture = "indian", .subdivisions = 12, .hits = makeRhythmHits(6, .{ 0, 2, 4, 6, 8, 10 }), .hit_count = 6 },
        .{ .name = "kaharwa", .culture = "indian", .subdivisions = 8, .hits = makeRhythmHits(2, .{ 0, 4 }), .hit_count = 2 },
        .{ .name = "dadra", .culture = "indian", .subdivisions = 6, .hits = makeRhythmHits(2, .{ 0, 3 }), .hit_count = 2 },
        .{ .name = "deepchandi", .culture = "indian", .subdivisions = 14, .hits = makeRhythmHits(4, .{ 0, 3, 7, 10 }), .hit_count = 4 },

        // Arabic iqa'at (8)
        .{ .name = "maqsum", .culture = "arabic", .subdivisions = 8, .hits = makeRhythmHits(4, .{ 0, 2, 4, 6 }), .hit_count = 4 },
        .{ .name = "baladi", .culture = "arabic", .subdivisions = 8, .hits = makeRhythmHits(4, .{ 0, 2, 4, 6 }), .hit_count = 4 },
        .{ .name = "saidi", .culture = "arabic", .subdivisions = 8, .hits = makeRhythmHits(4, .{ 0, 2, 4, 6 }), .hit_count = 4 },
        .{ .name = "malfuf", .culture = "arabic", .subdivisions = 4, .hits = makeRhythmHits(2, .{ 0, 2 }), .hit_count = 2 },
        .{ .name = "fallahi", .culture = "arabic", .subdivisions = 4, .hits = makeRhythmHits(2, .{ 0, 2 }), .hit_count = 2 },
        .{ .name = "sama_i_thaqil", .culture = "arabic", .subdivisions = 20, .hits = makeRhythmHits(5, .{ 0, 4, 8, 12, 16 }), .hit_count = 5 },
        .{ .name = "aqsaq", .culture = "arabic", .subdivisions = 18, .hits = makeRhythmHits(5, .{ 0, 4, 8, 12, 16 }), .hit_count = 5 },
        .{ .name = "dawr_hind", .culture = "arabic", .subdivisions = 14, .hits = makeRhythmHits(4, .{ 0, 4, 8, 12 }), .hit_count = 4 },
    };
};

pub fn getRhythm(name: []const u8) ?*const RhythmPattern {
    for (&RHYTHMS) |*r| {
        if (strieq(name, r.name)) return r;
    }
    return null;
}

// ══════════════════════════════════════════════════════════════════════
// Spline Wavetable Synth
// ══════════════════════════════════════════════════════════════════════

pub const ControlPoint = struct {
    x: f64,
    y: f64,
    value: f64,
};

pub const SplineWavetable = struct {
    points: []ControlPoint,
    table: []f64,
    table_size: usize,
    interp_matrix: []f64,
    allocator: Allocator,

    pub fn init(allocator: Allocator, table_size: usize, n_control_points: usize) !SplineWavetable {
        const points = try allocator.alloc(ControlPoint, n_control_points);
        @memset(points, ControlPoint{ .x = 0, .y = 0, .value = 0 });
        const table = try allocator.alloc(f64, table_size);
        @memset(table, 0);
        const interp_matrix = try allocator.alloc(f64, table_size * n_control_points);
        @memset(interp_matrix, 0);

        const swt = SplineWavetable{
            .points = points,
            .table = table,
            .table_size = table_size,
            .interp_matrix = interp_matrix,
            .allocator = allocator,
        };
        buildLattice(points);
        buildInterpMatrix(interp_matrix, points, n_control_points, table_size);
        return swt;
    }

    pub fn deinit(self: *SplineWavetable) void {
        self.allocator.free(self.points);
        self.allocator.free(self.table);
        self.allocator.free(self.interp_matrix);
    }

    pub fn setValues(self: *SplineWavetable, values: []const f64) void {
        const n = @min(values.len, self.points.len);
        for (0..n) |i| {
            self.points[i].value = values[i];
        }
    }

    pub fn reconstruct(self: *SplineWavetable) void {
        for (0..self.table_size) |i| {
            var s: f64 = 0.0;
            for (0..self.points.len) |j| {
                s += self.interp_matrix[i * self.points.len + j] * self.points[j].value;
            }
            self.table[i] = s;
        }
    }

    pub fn sample(self: *const SplineWavetable, phase: f64) f64 {
        const pos = phase * @as(f64, @floatFromInt(self.table_size));
        const idx_raw: usize = @intFromFloat(pos);
        const idx: usize = idx_raw % self.table_size;
        const idx_next = (idx + 1) % self.table_size;
        const frac = pos - @as(f64, @floatFromInt(idx_raw));
        return self.table[idx] * (1.0 - frac) + self.table[idx_next] * frac;
    }

    pub fn morph(a: *const SplineWavetable, b: *const SplineWavetable, t: f64, out: *SplineWavetable) void {
        const n = @min(a.points.len, b.points.len);
        for (0..n) |i| {
            out.points[i].value = (1.0 - t) * a.points[i].value + t * b.points[i].value;
        }
        out.reconstruct();
    }

    pub fn presetSine(self: *SplineWavetable) void {
        fitPreset(self, struct {
            fn gen(i: usize, n: usize) f64 {
                _ = n;
                return @sin(2.0 * PI * @as(f64, @floatFromInt(i)) / 2048.0);
            }
        }.gen);
    }

    pub fn presetSaw(self: *SplineWavetable) void {
        fitPreset(self, struct {
            fn gen(i: usize, n: usize) f64 {
                return 2.0 * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(n)) - 1.0;
            }
        }.gen);
    }

    pub fn presetSquare(self: *SplineWavetable) void {
        fitPreset(self, struct {
            fn gen(i: usize, n: usize) f64 {
                return if (@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(n)) < 0.5) @as(f64, 1.0) else -1.0;
            }
        }.gen);
    }

    pub fn presetTriangle(self: *SplineWavetable) void {
        fitPreset(self, struct {
            fn gen(i: usize, n: usize) f64 {
                const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(n));
                return 4.0 * @abs(t - 0.5) - 1.0;
            }
        }.gen);
    }

    pub fn reconstructionError(self: *const SplineWavetable, target: []const f64) f64 {
        const n = @min(self.table_size, target.len);
        var sum: f64 = 0.0;
        for (0..n) |i| {
            const d = self.table[i] - target[i];
            sum += d * d;
        }
        return @sqrt(sum / @as(f64, @floatFromInt(n)));
    }
};

// Internal: build Eisenstein lattice
fn buildLattice(pts: []ControlPoint) void {
    const n = pts.len;
    const R: i32 = @as(i32, @intFromFloat(@ceil(@sqrt(@as(f64, @floatFromInt(n)) / 3.0)))) + 2;
    const sqrt3_half = 0.86602540378443864676;

    const Candidate = struct { x: f64, y: f64, dist_sq: f64 };
    const Ri: i32 = if (R < 3) 3 else R;
    const max_cand: usize = @as(usize, @intCast(2 * Ri + 1)) * @as(usize, @intCast(2 * Ri + 1));
    // Use a stack buffer large enough for typical lattice scans
    var cands_buf: [2048]Candidate = undefined;
    const cand_count = @min(max_cand, cands_buf.len);
    var count: usize = 0;

    var ai: i32 = -Ri;
    while (ai <= Ri and count < cand_count) : (ai += 1) {
        var bi: i32 = -Ri;
        while (bi <= Ri and count < cand_count) : (bi += 1) {
            const x = @as(f64, @floatFromInt(ai)) - @as(f64, @floatFromInt(bi)) * 0.5;
            const y = @as(f64, @floatFromInt(bi)) * sqrt3_half;
            const d = x * x + y * y;
            cands_buf[count] = .{ .x = x, .y = y, .dist_sq = d };
            count += 1;
        }
    }

    // Sort by distance
    const S = struct {
        fn lessThan(_: void, a: Candidate, b: Candidate) bool {
            const da = @round(a.dist_sq * 1e9);
            const db = @round(b.dist_sq * 1e9);
            if (da < db) return true;
            if (da > db) return false;
            if (a.x < b.x) return true;
            if (a.x > b.x) return false;
            return a.y < b.y;
        }
    };
    std.sort.pdq(Candidate, cands_buf[0..count], {}, S.lessThan);

    // Find max distance for normalization
    var max_dist: f64 = 0;
    for (cands_buf[0..@min(n, count)]) |c| {
        const d = @sqrt(c.dist_sq);
        if (d > max_dist) max_dist = d;
    }
    if (max_dist < 1e-12) max_dist = 1.0;

    for (0..@min(n, count)) |i| {
        pts[i].x = cands_buf[i].x / max_dist;
        pts[i].y = cands_buf[i].y / max_dist;
        pts[i].value = 0.0;
    }
}

// Internal: build IDW² interpolation matrix
fn buildInterpMatrix(mat: []f64, pts: []const ControlPoint, n_pts: usize, table_size: usize) void {
    const eps: f64 = 1e-6;
    for (0..table_size) |i| {
        const qx: f64 = -1.0 + 2.0 * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(table_size));
        const qy: f64 = 0.0;
        var sum: f64 = 0.0;
        // Two-pass: compute weights then normalize
        var weights: [256]f64 = undefined;
        for (0..n_pts) |j| {
            const dx = qx - pts[j].x;
            const dy = qy - pts[j].y;
            const d2 = dx * dx + dy * dy;
            weights[j] = 1.0 / (d2 + eps);
            sum += weights[j];
        }
        for (0..n_pts) |j| {
            mat[i * n_pts + j] = weights[j] / sum;
        }
    }
}

// Internal: least-squares solver
fn lstsq(A: []const f64, y: []const f64, rows: usize, cols: usize, lambda: f64, x_out: []f64) void {
    // Build ATA = A^T A + λI  (cols × cols)
    var ATA: [4096]f64 = undefined; // enough for up to 64 control points
    var ATy: [256]f64 = undefined;

    @memset(ATA[0 .. cols * cols], 0);
    @memset(ATy[0..cols], 0);

    for (0..cols) |i| {
        for (0..cols) |j| {
            var s: f64 = 0.0;
            for (0..rows) |k| {
                s += A[k * cols + i] * A[k * cols + j];
            }
            ATA[i * cols + j] = s;
        }
        ATA[i * cols + i] += lambda;
        var s: f64 = 0.0;
        for (0..rows) |k| {
            s += A[k * cols + i] * y[k];
        }
        ATy[i] = s;
    }

    // Gauss-Jordan
    for (0..cols) |col| {
        var max_row = col;
        var max_val = @abs(ATA[col * cols + col]);
        for (col + 1..cols) |row| {
            const v = @abs(ATA[row * cols + col]);
            if (v > max_val) {
                max_val = v;
                max_row = row;
            }
        }
        if (max_row != col) {
            for (0..cols) |j| {
                const tmp = ATA[col * cols + j];
                ATA[col * cols + j] = ATA[max_row * cols + j];
                ATA[max_row * cols + j] = tmp;
            }
            const tmp = ATy[col];
            ATy[col] = ATy[max_row];
            ATy[max_row] = tmp;
        }
        const pivot_raw = ATA[col * cols + col];
        const pivot = if (@abs(pivot_raw) < 1e-15) @as(f64, 1e-15) else pivot_raw;
        for (0..cols) |j| ATA[col * cols + j] /= pivot;
        ATy[col] /= pivot;
        for (0..cols) |row| {
            if (row == col) continue;
            const factor = ATA[row * cols + col];
            for (0..cols) |j| ATA[row * cols + j] -= factor * ATA[col * cols + j];
            ATy[row] -= factor * ATy[col];
        }
    }
    @memcpy(x_out[0..cols], ATy[0..cols]);
}

fn fitPreset(swt: *SplineWavetable, comptime gen: fn (usize, usize) f64) void {
    const alloc = swt.allocator;
    const target = alloc.alloc(f64, swt.table_size) catch unreachable;
    defer alloc.free(target);
    for (0..swt.table_size) |i| {
        target[i] = gen(i, swt.table_size);
    }
    const values = alloc.alloc(f64, swt.points.len) catch unreachable;
    defer alloc.free(values);
    lstsq(swt.interp_matrix, target, swt.table_size, swt.points.len, 1e-4, values);
    swt.setValues(values);
    swt.reconstruct();
}

// ══════════════════════════════════════════════════════════════════════
// Core Constraint Primitives
// ══════════════════════════════════════════════════════════════════════

/// Eisenstein integer norm: a² - ab + b²
pub fn eisensteinNorm(a: i64, b: i64) i64 {
    return a * a - a * b + b * b;
}

/// Snap 2D point to Eisenstein lattice (a2 lattice)
pub fn a2Snap(x: f64, y: f64, epsilon: f64) [2]i64 {
    // The Eisenstein basis vectors: e1 = (1, 0), e2 = (0.5, sqrt(3)/2)
    const sqrt3_half = 0.86602540378443864676;
    // Solve: x = a + 0.5*b, y = sqrt3_half*b
    const b_f = y / sqrt3_half;
    const a_f = x - 0.5 * b_f;
    const a_r: i64 = @intFromFloat(@round(a_f));
    const b_r: i64 = @intFromFloat(@round(b_f));
    // Check if within epsilon
    const dx = x - (@as(f64, @floatFromInt(a_r)) + 0.5 * @as(f64, @floatFromInt(b_r)));
    const dy = y - sqrt3_half * @as(f64, @floatFromInt(b_r));
    if (dx * dx + dy * dy > epsilon * epsilon) {
        return .{ a_r, b_r }; // snap anyway
    }
    return .{ a_r, b_r };
}

/// Deadband filter: if val is within `band` of `center`, return center
pub fn deadband(val: f64, center: f64, band: f64) f64 {
    if (@abs(val - center) <= band) return center;
    return val;
}

/// Laman graph edge count: 2v - 3
pub fn lamanEdges(n: usize) usize {
    if (n < 2) return 0;
    return 2 * n - 3;
}

/// Check if a graph with n vertices and edge_count edges is rigid (Laman condition)
pub fn isLaman(n: usize, edge_count: usize) bool {
    if (n < 2) return edge_count == 0;
    return edge_count >= 2 * n - 3;
}

/// Holonomy check: product of signed values modulo should equal 1
pub fn holonomyCheck(values: []const f64, modulus: f64) bool {
    var product: f64 = 1.0;
    for (values) |v| {
        product *= v;
    }
    const diff = @abs(@mod(product, modulus) - 1.0);
    return diff < 1e-9;
}

// ══════════════════════════════════════════════════════════════════════
// Musical Cohomology
// ══════════════════════════════════════════════════════════════════════

pub const CohomologyResult = struct {
    h0: i32, // connected components
    h1: i32, // independent cycles
    emergence_detected: bool,
};

pub fn musicalCohomology(
    allocator: Allocator,
    chords: []const i32,
    transitions: []const [2]usize,
) !CohomologyResult {
    if (chords.len == 0) return .{ .h0 = 0, .h1 = 0, .emergence_detected = false };

    const n = chords.len;
    var adj = std.ArrayList(std.ArrayList(usize)).init(allocator);
    defer {
        for (adj.items) |*list| list.deinit();
        adj.deinit();
    }
    for (0..n) |_| {
        const list = std.ArrayList(usize).init(allocator);
        try adj.append(list);
    }

    // Build adjacency (undirected)
    for (transitions) |t| {
        const from = t[0];
        const to = t[1];
        if (from >= n or to >= n) continue;
        // Check duplicate from->to
        var dup = false;
        for (adj.items[from].items) |v| {
            if (v == to) { dup = true; break; }
        }
        if (!dup) try adj.items[from].append(to);
        // Check duplicate to->from
        dup = false;
        for (adj.items[to].items) |v| {
            if (v == from) { dup = true; break; }
        }
        if (!dup) try adj.items[to].append(from);
    }

    // BFS for connected components
    var visited = try allocator.alloc(bool, n);
    defer allocator.free(visited);
    @memset(visited, false);

    var h0: i32 = 0;
    var queue = std.ArrayList(usize).init(allocator);
    defer queue.deinit();

    for (0..n) |start| {
        if (visited[start]) continue;
        h0 += 1;
        try queue.append(start);
        visited[start] = true;
        while (queue.items.len > 0) {
            const u = queue.orderedRemove(0);
            for (adj.items[u].items) |v| {
                if (!visited[v]) {
                    visited[v] = true;
                    try queue.append(v);
                }
            }
        }
    }

    // Count unique undirected edges
    var unique_edges: usize = 0;
    for (adj.items) |list| unique_edges += list.items.len;
    unique_edges /= 2;

    const h1: i32 = @max(0, @as(i32, @intCast(unique_edges)) - @as(i32, @intCast(n)) + h0);
    return .{ .h0 = h0, .h1 = h1, .emergence_detected = h1 > 0 };
}

// ══════════════════════════════════════════════════════════════════════
// Utilities
// ══════════════════════════════════════════════════════════════════════

pub fn ratioToCents(ratio: f64) f64 {
    return 1200.0 * @log2(ratio);
}

pub fn approxEq(a: f64, b: f64, epsilon: f64) bool {
    return @abs(a - b) < epsilon;
}

// ══════════════════════════════════════════════════════════════════════
// Internal helpers
// ══════════════════════════════════════════════════════════════════════

fn strieq(a: []const u8, b: []const u8) bool {
    var ia: usize = 0;
    var ib: usize = 0;
    while (ia < a.len and ib < b.len) {
        var ca = a[ia];
        var cb = b[ib];
        if (ca >= 'A' and ca <= 'Z') ca += 32;
        if (cb >= 'A' and cb <= 'Z') cb += 32;
        if ((ca == '-' or ca == '_' or ca == ' ') and (cb == '-' or cb == '_' or cb == ' ')) {
            ia += 1;
            ib += 1;
            continue;
        }
        if (ca != cb) return false;
        ia += 1;
        ib += 1;
    }
    // Skip trailing separators
    while (ia < a.len and (a[ia] == '-' or a[ia] == '_' or a[ia] == ' ')) ia += 1;
    while (ib < b.len and (b[ib] == '-' or b[ib] == '_' or b[ib] == ' ')) ib += 1;
    return ia == a.len and ib == b.len;
}

fn round4(v: f64) f64 {
    return @round(v * 10000.0) / 10000.0;
}

fn makeRhythmHits(comptime nc: usize, comptime positions: [nc]usize) [MAX_HITS]bool {
    var arr: [MAX_HITS]bool = [_]bool{false} ** MAX_HITS;
    for (positions) |idx| arr[idx] = true;
    return arr;
}

// ══════════════════════════════════════════════════════════════════════
// Tests
// ══════════════════════════════════════════════════════════════════════

test "scales: getScale known" {
    try testing.expect(getScale("bhairavi") != null);
    try testing.expect(getScale("yaman") != null);
    try testing.expect(getScale("rast") != null);
    try testing.expect(getScale("in_scale") != null);
    try testing.expect(getScale("nonexistent") == null);
}

test "scales: case insensitive lookup" {
    try testing.expect(getScale("Bhairavi") != null);
    try testing.expect(getScale("RAGA_BHAIRAVI") == null); // names don't include "raga_"
    try testing.expect(getScale("BHAIRAVI") != null);
}

test "scales: total count is 36" {
    try testing.expect(SCALES.len == 36);
}

test "scales: bhairavi notes" {
    const s = getScale("bhairavi").?;
    try testing.expectEqualSlices(i32, s.notes[0..7], &[_]i32{ 0, 1, 3, 5, 7, 8, 10 });
    try testing.expectEqual(@as(usize, 7), s.note_count);
}

test "scales: yaman rasa" {
    const s = getScale("yaman").?;
    try testing.expectEqualStrings("romantic", s.rasa.?);
}

test "scales: arabic scale has null rasa" {
    const s = getScale("rast").?;
    try testing.expect(s.rasa == null);
}

test "scales: filter by culture" {
    var buf: [36]?*const WorldScale = undefined;
    const n = scalesByCulture("indian", &buf);
    try testing.expectEqual(@as(usize, 10), n);
}

test "scales: filter by culture japanese" {
    var buf: [36]?*const WorldScale = undefined;
    const n = scalesByCulture("japanese", &buf);
    try testing.expectEqual(@as(usize, 4), n);
}

test "scales: filter by culture arabic" {
    var buf: [36]?*const WorldScale = undefined;
    const n = scalesByCulture("arabic", &buf);
    try testing.expectEqual(@as(usize, 10), n);
}

test "scales: filter by culture african" {
    var buf: [36]?*const WorldScale = undefined;
    const n = scalesByCulture("african", &buf);
    try testing.expectEqual(@as(usize, 1), n);
}

test "scales: midi expansion" {
    var midi: [128]i32 = undefined;
    const count = scaleToMidi("bhairavi", 60, 2, &midi);
    try testing.expect(count > 0);
    try testing.expect(midi[0] == 60); // C4
    // Should be sorted
    for (0..count - 1) |i| {
        try testing.expect(midi[i] <= midi[i + 1]);
    }
}

test "scales: midi expansion nonexistent" {
    var midi: [128]i32 = undefined;
    const count = scaleToMidi("nonexistent", 60, 2, &midi);
    try testing.expectEqual(@as(usize, 0), count);
}

test "tuning: equal temperament" {
    try testing.expect(approxEq(equalTemperamentCents(0), 0.0, 0.01));
    try testing.expect(approxEq(equalTemperamentCents(1), 100.0, 0.01));
    try testing.expect(approxEq(equalTemperamentCents(12), 1200.0, 0.01));
}

test "tuning: just intonation ratios" {
    try testing.expect(approxEq(justIntonationCents(0), 0.0, 0.01));
    try testing.expect(justIntonationCents(4) > 380.0); // major third ~386 cents
    try testing.expect(justIntonationCents(4) < 395.0);
}

test "tuning: shruti 22 divisions" {
    try testing.expect(approxEq(shruti22Cents(0), 0.0, 0.01));
    try testing.expect(shruti22Cents(21) > 1100.0);
}

test "tuning: quarter tone 24" {
    try testing.expect(approxEq(quarterTone24Cents(1), 50.0, 0.01));
    try testing.expect(approxEq(quarterTone24Cents(24), 1200.0, 0.01));
}

test "tuning: pentatonic 5" {
    try testing.expect(approxEq(pentatonic5Cents(1), 240.0, 0.01));
}

test "tuning: meantone sorted" {
    const c0 = meantoneCents(0);
    const c11 = meantoneCents(11);
    try testing.expect(c0 >= 0.0);
    try testing.expect(c11 < 1200.0);
    // sorted
    for (0..11) |i| {
        try testing.expect(meantoneCents(@intCast(i)) <= meantoneCents(@intCast(i + 1)));
    }
}

test "tuning: pythagorean sorted" {
    for (0..11) |i| {
        try testing.expect(pythagoreanCents(@intCast(i)) <= pythagoreanCents(@intCast(i + 1)));
    }
}

test "tuning: snap to tuning" {
    const snapped = snapToTuning(102.0, &TUNING_EQUAL_TEMPERAMENT, 10.0);
    try testing.expect(approxEq(snapped, 100.0, 0.01));
}

test "tuning: snap out of range returns original" {
    const snapped = snapToTuning(102.0, &TUNING_EQUAL_TEMPERAMENT, 0.5);
    try testing.expect(approxEq(snapped, 102.0, 0.01));
}

test "tuning: all cents returns correct count" {
    var buf: [24]f64 = undefined;
    const n = tuningAllCents(&TUNING_EQUAL_TEMPERAMENT, &buf);
    try testing.expectEqual(@as(usize, 12), n);
    try testing.expect(approxEq(buf[0], 0.0, 0.01));
    try testing.expect(approxEq(buf[11], 1100.0, 0.01));
}

test "ornament: meend linear" {
    var buf: [11]f64 = undefined;
    meend(0.0, 10.0, 10, .linear, &buf);
    try testing.expect(approxEq(buf[0], 0.0, 0.001));
    try testing.expect(approxEq(buf[10], 10.0, 0.001));
    // Linear: midpoint should be ~5
    try testing.expect(approxEq(buf[5], 5.0, 0.001));
}

test "ornament: meend exponential" {
    var buf: [11]f64 = undefined;
    meend(0.0, 10.0, 10, .exponential, &buf);
    try testing.expect(approxEq(buf[0], 0.0, 0.001));
    try testing.expect(approxEq(buf[10], 10.0, 0.001));
    // Exponential: midpoint should be <5 (concave up)
    try testing.expect(buf[5] < 5.0);
}

test "ornament: meend logarithmic" {
    var buf: [11]f64 = undefined;
    meend(0.0, 10.0, 10, .logarithmic, &buf);
    try testing.expect(buf[5] > 5.0); // convex up
}

test "ornament: gamak oscillates" {
    var buf: [256]f64 = undefined;
    const n = gamak(60.0, 2.0, 2.0, 2, &buf);
    try testing.expect(n > 0);
    // First value should be at center
    try testing.expect(approxEq(buf[0], 60.0, 0.001));
    // Should oscillate above and below center
    var has_above = false;
    var has_below = false;
    for (buf[0..n]) |v| {
        if (v > 60.1) has_above = true;
        if (v < 59.9) has_below = true;
    }
    try testing.expect(has_above and has_below);
}

test "ornament: quarter bend up" {
    var buf: [64]f64 = undefined;
    const n = quarterBend(60.0, .up, 50.0, 10, &buf);
    try testing.expect(n > 10);
    // Should end back at start note
    try testing.expect(approxEq(buf[n - 1], 60.0, 0.001));
}

test "ornament: shakes" {
    var buf: [256]f64 = undefined;
    const n = shakes(60.0, 2.0, 1.0, &buf);
    try testing.expect(n > 0);
}

test "rhythms: get known" {
    try testing.expect(getRhythm("son_2_3") != null);
    try testing.expect(getRhythm("teental") != null);
    try testing.expect(getRhythm("maqsum") != null);
    try testing.expect(getRhythm("nonexistent") == null);
}

test "rhythms: total count is 26" {
    try testing.expect(RHYTHMS.len == 26);
}

test "rhythms: son_2_3 pattern" {
    const r = getRhythm("son_2_3").?;
    try testing.expectEqual(@as(usize, 16), r.subdivisions);
    try testing.expectEqual(@as(usize, 5), r.hit_count);
    try testing.expect(r.hits[0] == true);
    try testing.expect(r.hits[3] == true);
    try testing.expect(r.hits[1] == false);
}

test "rhythms: teental pattern" {
    const r = getRhythm("teental").?;
    try testing.expectEqual(@as(usize, 4), r.hit_count);
    try testing.expect(r.hits[0] == true);
    try testing.expect(r.hits[4] == true);
    try testing.expect(r.hits[8] == true);
    try testing.expect(r.hits[12] == true);
}

test "constraints: eisenstein norm" {
    try testing.expectEqual(@as(i64, 0), eisensteinNorm(0, 0));
    try testing.expectEqual(@as(i64, 1), eisensteinNorm(1, 0));
    try testing.expectEqual(@as(i64, 1), eisensteinNorm(0, 1));
    try testing.expectEqual(@as(i64, 1), eisensteinNorm(1, 1));
    try testing.expectEqual(@as(i64, 3), eisensteinNorm(2, 1));
}

test "constraints: laman edges" {
    try testing.expectEqual(@as(usize, 0), lamanEdges(1));
    try testing.expectEqual(@as(usize, 1), lamanEdges(2));
    try testing.expectEqual(@as(usize, 3), lamanEdges(3));
    try testing.expectEqual(@as(usize, 5), lamanEdges(4));
}

test "constraints: is laman" {
    try testing.expect(isLaman(2, 1));
    try testing.expect(!isLaman(2, 0));
    try testing.expect(isLaman(3, 3));
    try testing.expect(!isLaman(3, 2));
}

test "constraints: deadband" {
    try testing.expect(approxEq(deadband(5.0, 5.0, 0.1), 5.0, 0.001)); // returns center
    try testing.expect(approxEq(deadband(5.05, 5.0, 0.1), 5.0, 0.001)); // within band
    try testing.expect(approxEq(deadband(6.0, 5.0, 0.1), 6.0, 0.001)); // outside band
}

test "constraints: holonomy check" {
    const vals = [_]f64{ 2.0, 0.5 };
    // product = 1.0, mod 2.0 = 1.0 → check: |mod - 1.0| < eps
    try testing.expect(holonomyCheck(&vals, 2.0));
}

test "cohomology: single chord no transitions" {
    const chords = [_]i32{60};
    const trans = [_][2]usize{};
    const result = try musicalCohomology(testing.allocator, &chords, &trans);
    try testing.expectEqual(@as(i32, 1), result.h0);
    try testing.expectEqual(@as(i32, 0), result.h1);
    try testing.expect(!result.emergence_detected);
}

test "cohomology: cycle of 3 chords" {
    const chords = [_]i32{ 60, 64, 67 };
    const trans = [_][2]usize{ .{ 0, 1 }, .{ 1, 2 }, .{ 2, 0 } };
    const result = try musicalCohomology(testing.allocator, &chords, &trans);
    try testing.expectEqual(@as(i32, 1), result.h0);
    try testing.expectEqual(@as(i32, 1), result.h1);
    try testing.expect(result.emergence_detected);
}

test "cohomology: disconnected components" {
    const chords = [_]i32{ 60, 64 };
    const trans = [_][2]usize{};
    const result = try musicalCohomology(testing.allocator, &chords, &trans);
    try testing.expectEqual(@as(i32, 2), result.h0);
}

test "utility: ratio to cents" {
    try testing.expect(approxEq(ratioToCents(2.0), 1200.0, 0.01));
    try testing.expect(approxEq(ratioToCents(1.0), 0.0, 0.01));
}

test "utility: approx eq" {
    try testing.expect(approxEq(1.0, 1.0001, 0.001));
    try testing.expect(!approxEq(1.0, 1.1, 0.001));
}

test "strieq: basic" {
    try testing.expect(strieq("hello", "Hello"));
    try testing.expect(strieq("son_2_3", "son-2-3"));
    try testing.expect(!strieq("hello", "world"));
}

test "spline: init and deinit" {
    var swt = try SplineWavetable.init(testing.allocator, 256, 8);
    defer swt.deinit();
    try testing.expectEqual(@as(usize, 256), swt.table_size);
    try testing.expectEqual(@as(usize, 8), swt.points.len);
}

test "spline: reconstruct flat" {
    var swt = try SplineWavetable.init(testing.allocator, 256, 8);
    defer swt.deinit();
    // All zero values → all zero table
    swt.reconstruct();
    for (swt.table) |v| {
        try testing.expect(approxEq(v, 0.0, 0.01));
    }
}

test "spline: preset sine" {
    var swt = try SplineWavetable.init(testing.allocator, 256, 16);
    defer swt.deinit();
    swt.presetSine();
    // Check that table is not all zeros
    var nonzero = false;
    for (swt.table) |v| {
        if (@abs(v) > 0.01) nonzero = true;
    }
    try testing.expect(nonzero);
}

test "spline: preset saw" {
    var swt = try SplineWavetable.init(testing.allocator, 256, 16);
    defer swt.deinit();
    swt.presetSaw();
    var nonzero = false;
    for (swt.table) |v| {
        if (@abs(v) > 0.01) nonzero = true;
    }
    try testing.expect(nonzero);
}

test "spline: preset square" {
    var swt = try SplineWavetable.init(testing.allocator, 256, 16);
    defer swt.deinit();
    swt.presetSquare();
    var nonzero = false;
    for (swt.table) |v| {
        if (@abs(v) > 0.01) nonzero = true;
    }
    try testing.expect(nonzero);
}

test "spline: preset triangle" {
    var swt = try SplineWavetable.init(testing.allocator, 256, 16);
    defer swt.deinit();
    swt.presetTriangle();
    var nonzero = false;
    for (swt.table) |v| {
        if (@abs(v) > 0.01) nonzero = true;
    }
    try testing.expect(nonzero);
}

test "spline: sample at boundaries" {
    var swt = try SplineWavetable.init(testing.allocator, 256, 16);
    defer swt.deinit();
    swt.presetSine();
    _ = swt.sample(0.0);
    _ = swt.sample(0.5);
    _ = swt.sample(0.999);
}

test "spline: morph between two wavetables" {
    var a = try SplineWavetable.init(testing.allocator, 256, 8);
    defer a.deinit();
    var b = try SplineWavetable.init(testing.allocator, 256, 8);
    defer b.deinit();
    var out = try SplineWavetable.init(testing.allocator, 256, 8);
    defer out.deinit();

    a.presetSine();
    b.presetSaw();
    SplineWavetable.morph(&a, &b, 0.5, &out);
    // Should have non-zero values
    var nonzero = false;
    for (out.table) |v| {
        if (@abs(v) > 0.01) nonzero = true;
    }
    try testing.expect(nonzero);
}

test "spline: reconstruction error" {
    var swt = try SplineWavetable.init(testing.allocator, 256, 32);
    defer swt.deinit();
    swt.presetSine();

    // Generate target sine
    var target: [256]f64 = undefined;
    for (0..256) |i| {
        target[i] = @sin(2.0 * PI * @as(f64, @floatFromInt(i)) / 2048.0);
    }
    const err = swt.reconstructionError(&target);
    // With 32 control points, error should be reasonable
    try testing.expect(err < 1.0);
}
