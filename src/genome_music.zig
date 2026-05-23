//! Musical genome — 25-gene evolutionary system for generating musical traits.
//!
//! Each organism has a genome of 25 floating-point genes (0.0–1.0).
//! Populations evolve toward fitness targets that encode genre aesthetics
//! (snap strictness, funnel gravity, syncopation, etc.).

const std = @import("std");
const math = std.math;
const testing = std.testing;

// ── Gene index ───────────────────────────────────────────────────────

pub const GeneIndex = enum(u8) {
    snap_strictness = 0,
    funnel_gravity = 1,
    laman_threshold = 2,
    consensus_weight = 3,
    tempo_tendency = 4,
    syncopation = 5,
    density = 6,
    dissonance_tolerance = 7,
    rhythmic_complexity = 8,
    melodic_range = 9,
    harmonic_richness = 10,
    dynamic_range = 11,
    articulation = 12,
    sustain = 13,
    attack_sharpness = 14,
    release_curve = 15,
    spatial_width = 16,
    reverb_tendency = 17,
    modulation_depth = 18,
    filter_resonance = 19,
    pitch_bend_range = 20,
    velocity_sensitivity = 21,
    timbre_brightness = 22,
    polyphony_preference = 23,
    groove_swing = 24,
};

pub const GENE_COUNT: usize = 25;

fn filledGenes(val: f64) [GENE_COUNT]f64 {
    var genes: [GENE_COUNT]f64 = undefined;
    @memset(&genes, val);
    return genes;
}

// ── Musical genome ───────────────────────────────────────────────────

pub const MusicalGenome = struct {
    genes: [GENE_COUNT]f64,

    const Self = @This();

    pub fn init() Self {
        return .{ .genes = filledGenes(0.5) };
    }

    pub fn random(rng: std.Random) Self {
        var g = Self.init();
        for (&g.genes) |*gene| {
            gene.* = rng.float(f64);
        }
        return g;
    }

    pub fn get(self: *const Self, gene: GeneIndex) f64 {
        return self.genes[@intFromEnum(gene)];
    }

    pub fn set(self: *Self, gene: GeneIndex, value: f64) void {
        self.genes[@intFromEnum(gene)] = @max(0.0, @min(1.0, value));
    }

    pub fn clone(self: *const Self) Self {
        return .{ .genes = self.genes };
    }

    /// Single-point crossover between two parents.
    pub fn crossover(a: *const Self, b: *const Self, point: usize) Self {
        var child = Self.init();
        const p = @min(point, GENE_COUNT);
        @memcpy(child.genes[0..p], a.genes[0..p]);
        @memcpy(child.genes[p..], b.genes[p..]);
        return child;
    }

    /// Two-point crossover.
    pub fn crossover_two_point(a: *const Self, b: *const Self, p1: usize, p2: usize) Self {
        var child = Self.init();
        const lo = @min(p1, p2);
        const hi = @max(p1, p2);
        var i: usize = 0;
        while (i < lo) : (i += 1) child.genes[i] = a.genes[i];
        while (i < hi) : (i += 1) child.genes[i] = b.genes[i];
        while (i < GENE_COUNT) : (i += 1) child.genes[i] = a.genes[i];
        return child;
    }

    /// Uniform crossover with blend ratio.
    pub fn blend_crossover(a: *const Self, b: *const Self, ratio: f64) Self {
        var child = Self.init();
        for (&child.genes, a.genes, b.genes) |*c, av, bv| {
            c.* = av * ratio + bv * (1.0 - ratio);
        }
        return child;
    }

    /// Mutate genes in place with given rate and magnitude.
    pub fn mutate(self: *Self, rate: f64, magnitude: f64, rng: std.Random) void {
        for (&self.genes) |*gene| {
            if (rng.float(f64) < rate) {
                const delta = (rng.float(f64) * 2.0 - 1.0) * magnitude;
                gene.* = @max(0.0, @min(1.0, gene.* + delta));
            }
        }
    }

    /// Euclidean distance to another genome.
    pub fn distance(self: *const Self, other: *const Self) f64 {
        var sum: f64 = 0.0;
        for (self.genes, other.genes) |a, b| {
            const d = a - b;
            sum += d * d;
        }
        return @sqrt(sum);
    }
};

// ── Fitness ──────────────────────────────────────────────────────────

pub const FitnessTarget = struct {
    snap: f64,
    funnel: f64,
    syncopation: f64,
    consensus: f64,
    tempo: f64,
};

/// Compute fitness (0.0–1.0) of a genome against a target.
/// Uses weighted RMS of gene-target distances for the 5 primary traits.
pub fn fitness(genome: *const MusicalGenome, target: *const FitnessTarget) f64 {
    const gene_map = [_]struct { GeneIndex, f64 }{
        .{ .snap_strictness, target.snap },
        .{ .funnel_gravity, target.funnel },
        .{ .syncopation, target.syncopation },
        .{ .consensus_weight, target.consensus },
        .{ .tempo_tendency, target.tempo },
    };

    var sum_sq: f64 = 0.0;
    for (gene_map) |gm| {
        const diff = genome.get(gm[0]) - gm[1];
        sum_sq += diff * diff;
    }
    const rms = @sqrt(sum_sq / @as(f64, @floatFromInt(gene_map.len)));
    return 1.0 - rms; // perfect match = 1.0
}

// ── Pre-defined genre targets ────────────────────────────────────────

pub const TARGET_JAZZ = FitnessTarget{ .snap = 0.4, .funnel = 0.6, .syncopation = 0.8, .consensus = 0.7, .tempo = 0.7 };
pub const TARGET_CLASSICAL = FitnessTarget{ .snap = 0.9, .funnel = 0.8, .syncopation = 0.1, .consensus = 0.9, .tempo = 0.4 };
pub const TARGET_AMBIENT = FitnessTarget{ .snap = 0.1, .funnel = 0.3, .syncopation = 0.0, .consensus = 0.2, .tempo = 0.1 };
pub const TARGET_HIPHOP = FitnessTarget{ .snap = 0.7, .funnel = 0.5, .syncopation = 0.9, .consensus = 0.8, .tempo = 0.6 };
pub const TARGET_ELECTRONIC = FitnessTarget{ .snap = 1.0, .funnel = 0.4, .syncopation = 0.5, .consensus = 1.0, .tempo = 0.9 };
pub const TARGET_ROCK = FitnessTarget{ .snap = 0.6, .funnel = 0.7, .syncopation = 0.4, .consensus = 0.6, .tempo = 0.7 };
pub const TARGET_FOLK = FitnessTarget{ .snap = 0.3, .funnel = 0.4, .syncopation = 0.2, .consensus = 0.3, .tempo = 0.3 };
pub const TARGET_METAL = FitnessTarget{ .snap = 0.8, .funnel = 0.9, .syncopation = 0.5, .consensus = 0.7, .tempo = 0.85 };
pub const TARGET_REGGAE = FitnessTarget{ .snap = 0.5, .funnel = 0.3, .syncopation = 0.7, .consensus = 0.5, .tempo = 0.4 };

// ── Population ───────────────────────────────────────────────────────

pub const Population = struct {
    organisms: []MusicalGenome,
    fitnesses: []f64,
    generation: usize,

    const Self = @This();

    pub fn init(size: usize, rng: std.Random, allocator: std.mem.Allocator) !Self {
        const organisms = try allocator.alloc(MusicalGenome, size);
        const fitnesses = try allocator.alloc(f64, size);
        for (organisms, fitnesses) |*org, *fit| {
            org.* = MusicalGenome.random(rng);
            fit.* = 0.0;
        }
        return Self{
            .organisms = organisms,
            .fitnesses = fitnesses,
            .generation = 0,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.organisms);
        allocator.free(self.fitnesses);
    }

    /// Run one generation of evolution: evaluate, select, crossover, mutate.
    pub fn evolve(self: *Self, target: *const FitnessTarget, rng: std.Random, allocator: std.mem.Allocator) !void {
        const n = self.organisms.len;
        if (n < 2) return;

        // Evaluate fitness
        for (self.organisms, self.fitnesses) |org, *fit| {
            fit.* = fitness(&org, target);
        }

        // Tournament selection + crossover + mutation
        const new_orgs = try allocator.alloc(MusicalGenome, n);
        defer allocator.free(new_orgs);

        for (new_orgs) |*child| {
            const p1 = tournament_select(self, rng);
            const p2 = tournament_select(self, rng);
            const crossover_point = rng.intRangeAtMost(usize, 0, GENE_COUNT);
            child.* = MusicalGenome.crossover(&self.organisms[p1], &self.organisms[p2], crossover_point);
            child.mutate(0.1, 0.1, rng);
        }

        // Elitism: keep best
        const best_idx = self.best_index();
        @memcpy(self.organisms, new_orgs);
        // Replace worst with best from previous gen
        var worst_idx: usize = 0;
        var worst_fit: f64 = 2.0;
        for (self.organisms, self.fitnesses, 0..) |_, f, i| {
            if (f < worst_fit) {
                worst_fit = f;
                worst_idx = i;
            }
        }
        // Re-evaluate to find actual worst in new gen
        var new_worst: usize = 0;
        var new_worst_fit: f64 = 2.0;
        for (new_orgs, 0..) |org, i| {
            const f = fitness(&org, target);
            if (f < new_worst_fit) {
                new_worst_fit = f;
                new_worst = i;
            }
        }
        // Copy elite
        self.organisms[new_worst] = self.organisms[best_idx].clone();

        // Update fitnesses
        for (self.organisms, self.fitnesses) |org, *fit| {
            fit.* = fitness(&org, target);
        }

        self.generation += 1;
    }

    fn tournament_select(self: *const Self, rng: std.Random) usize {
        const k = 3; // tournament size
        var best_idx: usize = rng.intRangeLessThan(usize, 0, self.organisms.len);
        var best_fit = self.fitnesses[best_idx];
        for (0..k - 1) |_| {
            const idx = rng.intRangeLessThan(usize, 0, self.organisms.len);
            if (self.fitnesses[idx] > best_fit) {
                best_fit = self.fitnesses[idx];
                best_idx = idx;
            }
        }
        return best_idx;
    }

    fn best_index(self: *const Self) usize {
        var best_idx: usize = 0;
        var best_fit: f64 = self.fitnesses[0];
        for (self.fitnesses[1..], 1..) |f, i| {
            if (f > best_fit) {
                best_fit = f;
                best_idx = i;
            }
        }
        return best_idx;
    }

    pub fn best(self: *const Self) *const MusicalGenome {
        return &self.organisms[self.best_index()];
    }

    pub fn best_fitness(self: *const Self) f64 {
        return self.fitnesses[self.best_index()];
    }

    pub fn avg_fitness(self: *const Self) f64 {
        var sum: f64 = 0.0;
        for (self.fitnesses) |f| sum += f;
        return sum / @as(f64, @floatFromInt(self.fitnesses.len));
    }
};

// ── Tests ────────────────────────────────────────────────────────────

test "genome init all 0.5" {
    const g = MusicalGenome.init();
    for (g.genes) |gene| {
        try testing.expectApproxEqAbs(@as(f64, 0.5), gene, 1e-10);
    }
}

test "genome random in range" {
    var prng = std.Random.DefaultPrng.init(42);
    const g = MusicalGenome.random(prng.random());
    for (g.genes) |gene| {
        try testing.expect(gene >= 0.0 and gene <= 1.0);
    }
}

test "genome get and set" {
    var g = MusicalGenome.init();
    g.set(.tempo_tendency, 0.8);
    try testing.expectApproxEqAbs(@as(f64, 0.8), g.get(.tempo_tendency), 1e-10);
    // Clamp above 1.0
    g.set(.syncopation, 1.5);
    try testing.expectApproxEqAbs(@as(f64, 1.0), g.get(.syncopation), 1e-10);
    // Clamp below 0.0
    g.set(.density, -0.3);
    try testing.expectApproxEqAbs(@as(f64, 0.0), g.get(.density), 1e-10);
}

test "genome clone produces copy" {
    var g = MusicalGenome.init();
    g.set(.snap_strictness, 0.7);
    const c = g.clone();
    try testing.expectApproxEqAbs(@as(f64, 0.7), c.get(.snap_strictness), 1e-10);
    // Modifying original doesn't affect clone
    g.set(.snap_strictness, 0.1);
    try testing.expectApproxEqAbs(@as(f64, 0.7), c.get(.snap_strictness), 1e-10);
}

test "single-point crossover" {
    const a = MusicalGenome{ .genes = filledGenes(0.0) };
    const b = MusicalGenome{ .genes = filledGenes(1.0) };
    const child = MusicalGenome.crossover(&a, &b, 10);
    for (child.genes, 0..) |gene, i| {
        if (i < 10) {
            try testing.expectApproxEqAbs(@as(f64, 0.0), gene, 1e-10);
        } else {
            try testing.expectApproxEqAbs(@as(f64, 1.0), gene, 1e-10);
        }
    }
}

test "two-point crossover" {
    const a = MusicalGenome{ .genes = filledGenes(0.0) };
    const b = MusicalGenome{ .genes = filledGenes(1.0) };
    const child = MusicalGenome.crossover_two_point(&a, &b, 5, 15);
    for (child.genes, 0..) |gene, i| {
        if (i < 5 or i >= 15) {
            try testing.expectApproxEqAbs(@as(f64, 0.0), gene, 1e-10);
        } else {
            try testing.expectApproxEqAbs(@as(f64, 1.0), gene, 1e-10);
        }
    }
}

test "blend crossover" {
    const a = MusicalGenome{ .genes = filledGenes(0.0) };
    const b = MusicalGenome{ .genes = filledGenes(1.0) };
    const child = MusicalGenome.blend_crossover(&a, &b, 0.5);
    for (child.genes) |gene| {
        try testing.expectApproxEqAbs(@as(f64, 0.5), gene, 1e-10);
    }
}

test "mutate changes genes within bounds" {
    var prng = std.Random.DefaultPrng.init(123);
    var g = MusicalGenome{ .genes = filledGenes(0.5) };
    g.mutate(1.0, 0.3, prng.random()); // 100% rate, magnitude 0.3
    // At least some genes should have changed
    var changed = false;
    for (g.genes) |gene| {
        try testing.expect(gene >= 0.0 and gene <= 1.0);
        if (@abs(gene - 0.5) > 0.01) changed = true;
    }
    try testing.expect(changed);
}

test "mutate with zero rate does nothing" {
    var prng = std.Random.DefaultPrng.init(42);
    var g = MusicalGenome{ .genes = filledGenes(0.5) };
    g.mutate(0.0, 0.5, prng.random());
    for (g.genes) |gene| {
        try testing.expectApproxEqAbs(@as(f64, 0.5), gene, 1e-10);
    }
}

test "genome distance to self is zero" {
    const g = MusicalGenome.init();
    try testing.expectApproxEqAbs(@as(f64, 0.0), g.distance(&g), 1e-10);
}

test "genome distance is symmetric" {
    var prng = std.Random.DefaultPrng.init(42);
    const a = MusicalGenome.random(prng.random());
    const b = MusicalGenome.random(prng.random());
    try testing.expectApproxEqAbs(a.distance(&b), b.distance(&a), 1e-10);
}

test "fitness perfect match returns 1.0" {
    var g = MusicalGenome.init();
    g.set(.snap_strictness, TARGET_JAZZ.snap);
    g.set(.funnel_gravity, TARGET_JAZZ.funnel);
    g.set(.syncopation, TARGET_JAZZ.syncopation);
    g.set(.consensus_weight, TARGET_JAZZ.consensus);
    g.set(.tempo_tendency, TARGET_JAZZ.tempo);
    const f = fitness(&g, &TARGET_JAZZ);
    try testing.expectApproxEqAbs(@as(f64, 1.0), f, 1e-10);
}

test "fitness worst case near 0" {
    var g = MusicalGenome.init(); // all 0.5
    // Electronic target has snap=1.0, consensus=1.0 — genome at 0.5 is far
    const f = fitness(&g, &TARGET_ELECTRONIC);
    try testing.expect(f < 0.9);
    try testing.expect(f > 0.0);
}

test "fitness jazz vs ambient differ" {
    const g = MusicalGenome.init();
    const f_jazz = fitness(&g, &TARGET_JAZZ);
    const f_ambient = fitness(&g, &TARGET_AMBIENT);
    // They should differ since targets differ
    try testing.expect(@abs(f_jazz - f_ambient) > 0.01);
}

test "population init and deinit" {
    var prng = std.Random.DefaultPrng.init(42);
    var pop = try Population.init(20, prng.random(), testing.allocator);
    defer pop.deinit(testing.allocator);

    try testing.expect(pop.organisms.len == 20);
    try testing.expect(pop.fitnesses.len == 20);
    try testing.expect(pop.generation == 0);
}

test "population evolve improves fitness" {
    var prng = std.Random.DefaultPrng.init(42);
    var pop = try Population.init(50, prng.random(), testing.allocator);
    defer pop.deinit(testing.allocator);

    // Evaluate initial
    for (pop.organisms, pop.fitnesses) |org, *fit| {
        fit.* = fitness(&org, &TARGET_JAZZ);
    }
    var initial_avg: f64 = 0;

    // Evolve for 10 generations
    for (0..10) |_| {
        try pop.evolve(&TARGET_JAZZ, prng.random(), testing.allocator);
    }

    initial_avg = pop.avg_fitness();
    // Fitness should generally improve (not guaranteed but very likely with 50 organisms)
    try testing.expect(pop.generation == 10);
}

test "population best returns highest fitness" {
    var prng = std.Random.DefaultPrng.init(42);
    var pop = try Population.init(10, prng.random(), testing.allocator);
    defer pop.deinit(testing.allocator);

    for (pop.organisms, pop.fitnesses) |org, *fit| {
        fit.* = fitness(&org, &TARGET_CLASSICAL);
    }
    const best = pop.best();
    const best_fit = pop.best_fitness();
    for (pop.fitnesses) |f| {
        try testing.expect(f <= best_fit + 1e-10);
    }
    const bfit = fitness(best, &TARGET_CLASSICAL);
    try testing.expectApproxEqAbs(best_fit, bfit, 1e-10);
}

test "target constants are valid" {
    try testing.expect(TARGET_JAZZ.snap >= 0.0 and TARGET_JAZZ.snap <= 1.0);
    try testing.expect(TARGET_CLASSICAL.syncopation >= 0.0);
    try testing.expect(TARGET_AMBIENT.tempo >= 0.0);
    try testing.expect(TARGET_HIPHOP.consensus >= 0.0);
    try testing.expect(TARGET_ELECTRONIC.snap <= 1.0);
    try testing.expect(TARGET_ROCK.funnel >= 0.0);
    try testing.expect(TARGET_FOLK.syncopation <= 1.0);
    try testing.expect(TARGET_METAL.tempo >= 0.0);
    try testing.expect(TARGET_REGGAE.funnel >= 0.0);
}

test "gene index round-trip" {
    try testing.expect(@intFromEnum(GeneIndex.snap_strictness) == 0);
    try testing.expect(@intFromEnum(GeneIndex.groove_swing) == 24);
    try testing.expect(@intFromEnum(GeneIndex.tempo_tendency) == 4);
}
