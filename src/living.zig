//! Living constraint system — MusicalCell, JazzSession, TradingFours, CallAndResponse, Vamp.
//!
//! Biological metaphor: cells have genomes, epigenetic markers, transcription factors.
//! They express musical output based on shared context and inter-cellular signaling.
//! A JazzSession orchestrates multiple cells through phases.

const std = @import("std");
const math = std.math;
const testing = std.testing;
const Allocator = std.mem.Allocator;

// ── Constants ────────────────────────────────────────────────────────

pub const GENOME_SIZE: usize = 25;
pub const BEATS_PER_BAR: usize = 4;
pub const BARS_PER_PHASE: usize = 8;
pub const MAX_EVENTS: usize = 32;
pub const MAX_SIGNALS: usize = 8;
pub const MAX_TFS: usize = 4;
pub const MAX_CHORD: usize = 4;
pub const MAX_SCALE: usize = 7;

// ── Gene indices ─────────────────────────────────────────────────────

pub const Gene = enum(u8) {
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

// ── MIDI Event ───────────────────────────────────────────────────────

pub const MidiEvent = struct {
    note: u8,
    velocity: u8,
    duration_beats: f64,
    offset_beats: f64,
    channel: u8,

    pub fn init(note: u8, velocity: u8, duration: f64, offset: f64, channel: u8) MidiEvent {
        return .{ .note = note, .velocity = velocity, .duration_beats = duration, .offset_beats = offset, .channel = channel };
    }

    pub fn quantize16th(self: *MidiEvent) void {
        const sixteenth: f64 = 0.25;
        self.offset_beats = @round(self.offset_beats / sixteenth) * sixteenth;
        self.duration_beats = @max(@round(self.duration_beats / sixteenth) * sixteenth, sixteenth);
    }
};

// ── Signal Map ───────────────────────────────────────────────────────

pub const SignalEntry = struct {
    key: [32]u8,
    key_len: usize,
    value: f64,
};

pub const SignalMap = struct {
    entries: [MAX_SIGNALS]SignalEntry,
    count: usize,

    pub fn init() SignalMap {
        return .{
            .entries = undefined,
            .count = 0,
        };
    }

    pub fn set(self: *SignalMap, key: []const u8, value: f64) void {
        // Update existing
        for (0..self.count) |i| {
            if (std.mem.eql(u8, self.entries[i].key[0..self.entries[i].key_len], key)) {
                self.entries[i].value = value;
                return;
            }
        }
        // Add new
        if (self.count < MAX_SIGNALS) {
            const i = self.count;
            @memset(&self.entries[i].key, 0);
            const len = @min(key.len, 32);
            @memcpy(self.entries[i].key[0..len], key[0..len]);
            self.entries[i].key_len = len;
            self.entries[i].value = value;
            self.count += 1;
        }
    }

    pub fn get(self: *const SignalMap, key: []const u8) ?f64 {
        for (0..self.count) |i| {
            if (std.mem.eql(u8, self.entries[i].key[0..self.entries[i].key_len], key)) {
                return self.entries[i].value;
            }
        }
        return null;
    }

    pub fn clear(self: *SignalMap) void {
        self.count = 0;
    }
};

// ── Cell Output ──────────────────────────────────────────────────────

pub const CellOutput = struct {
    events: [MAX_EVENTS]MidiEvent,
    event_count: usize,
    signals: SignalMap,

    pub fn init() CellOutput {
        return .{
            .events = undefined,
            .event_count = 0,
            .signals = SignalMap.init(),
        };
    }

    pub fn addEvent(self: *CellOutput, event: MidiEvent) void {
        if (self.event_count < MAX_EVENTS) {
            self.events[self.event_count] = event;
            self.event_count += 1;
        }
    }

    pub fn isEmpty(self: *const CellOutput) bool {
        return self.event_count == 0;
    }
};

// ── Cell Role ────────────────────────────────────────────────────────

pub const CellRole = enum(u8) {
    piano = 0,
    bass = 1,
    drums = 2,
    sax = 3,

    pub fn defaultChannel(self: CellRole) u8 {
        return switch (self) {
            .piano => 0,
            .bass => 1,
            .drums => 9,
            .sax => 2,
        };
    }

    pub fn velocityRange(self: CellRole) struct { lo: u8, hi: u8 } {
        return switch (self) {
            .piano => .{ .lo = 40, .hi = 100 },
            .bass => .{ .lo = 50, .hi = 110 },
            .drums => .{ .lo = 60, .hi = 120 },
            .sax => .{ .lo = 45, .hi = 105 },
        };
    }

    pub fn register(self: CellRole) struct { lo: u8, hi: u8 } {
        return switch (self) {
            .piano => .{ .lo = 48, .hi = 84 },
            .bass => .{ .lo = 28, .hi = 55 },
            .drums => .{ .lo = 35, .hi = 81 },
            .sax => .{ .lo = 54, .hi = 91 },
        };
    }
};

// ── Transcription Factor ─────────────────────────────────────────────

pub const TranscriptionFactor = struct {
    gene_index: usize,
    sensitivity: f64,

    pub fn init(gene_index: usize, sensitivity: f64) TranscriptionFactor {
        return .{ .gene_index = gene_index, .sensitivity = sensitivity };
    }

    pub fn activation(self: *const TranscriptionFactor, genome: *const [GENOME_SIZE]f64) f64 {
        if (self.gene_index >= GENOME_SIZE) return 0.0;
        const val = genome[self.gene_index];
        return self.sensitivity * val / (1.0 + @abs(self.sensitivity * val));
    }
};

// ── Shared Context ───────────────────────────────────────────────────

pub const SharedContext = struct {
    key: u8,
    tempo: f64,
    energy: f64,
    beat: usize,
    bar: usize,
    chord: [MAX_CHORD]u8,
    chord_len: usize,

    pub fn init(key: u8, tempo: f64) SharedContext {
        var ctx = SharedContext{
            .key = key,
            .tempo = tempo,
            .energy = 0.5,
            .beat = 0,
            .bar = 0,
            .chord = undefined,
            .chord_len = 3,
        };
        ctx.chord[0] = 0;
        ctx.chord[1] = 4;
        ctx.chord[2] = 7;
        return ctx;
    }

    pub fn scaleNotes(self: *const SharedContext) [MAX_SCALE]u8 {
        const major = [_]i32{ 0, 2, 4, 5, 7, 9, 11 };
        var notes: [MAX_SCALE]u8 = undefined;
        for (&notes, major) |*n, interval| {
            n.* = @intCast(@as(i32, self.key) + interval);
        }
        return notes;
    }

    pub fn chordTones(self: *const SharedContext) [MAX_CHORD]u8 {
        var tones: [MAX_CHORD]u8 = [_]u8{0} ** MAX_CHORD;
        const len = @min(self.chord_len, MAX_CHORD);
        for (0..len) |i| {
            tones[i] = self.key + self.chord[i];
        }
        return tones;
    }

    pub fn tick(self: *SharedContext) void {
        self.beat += 1;
        if (self.beat >= BEATS_PER_BAR) {
            self.beat = 0;
            self.bar += 1;
        }
    }
};

// ── Musical Cell ─────────────────────────────────────────────────────

pub const MusicalCell = struct {
    genome: [GENOME_SIZE]f64,
    epigenetic: [GENOME_SIZE]f64,
    tfs: [MAX_TFS]TranscriptionFactor,
    tf_count: usize,
    role: CellRole,
    active: bool,
    solo: bool,
    accumulated_signals: SignalMap,
    history_count: usize,

    const Self = @This();

    pub fn init(role: CellRole) Self {
        var cell = Self{
            .genome = undefined,
            .epigenetic = undefined,
            .tfs = undefined,
            .tf_count = 0,
            .role = role,
            .active = true,
            .solo = false,
            .accumulated_signals = SignalMap.init(),
            .history_count = 0,
        };

        // Default genome
        @memset(&cell.genome, 0.5);
        switch (role) {
            .piano => {
                cell.genome[@intFromEnum(Gene.harmonic_richness)] = 0.7;
                cell.genome[@intFromEnum(Gene.polyphony_preference)] = 0.8;
                cell.genome[@intFromEnum(Gene.melodic_range)] = 0.6;
                cell.genome[@intFromEnum(Gene.syncopation)] = 0.6;
            },
            .bass => {
                cell.genome[@intFromEnum(Gene.density)] = 0.4;
                cell.genome[@intFromEnum(Gene.groove_swing)] = 0.5;
                cell.genome[@intFromEnum(Gene.dynamic_range)] = 0.3;
                cell.genome[@intFromEnum(Gene.syncopation)] = 0.4;
            },
            .drums => {
                cell.genome[@intFromEnum(Gene.rhythmic_complexity)] = 0.8;
                cell.genome[@intFromEnum(Gene.density)] = 0.7;
                cell.genome[@intFromEnum(Gene.syncopation)] = 0.7;
                cell.genome[@intFromEnum(Gene.dynamic_range)] = 0.6;
            },
            .sax => {
                cell.genome[@intFromEnum(Gene.articulation)] = 0.7;
                cell.genome[@intFromEnum(Gene.melodic_range)] = 0.8;
                cell.genome[@intFromEnum(Gene.dissonance_tolerance)] = 0.6;
                cell.genome[@intFromEnum(Gene.syncopation)] = 0.7;
            },
        }

        // Default epigenetic
        @memset(&cell.epigenetic, 0.5);

        // Default TFs
        switch (role) {
            .piano => {
                cell.tfs[0] = TranscriptionFactor.init(@intFromEnum(Gene.harmonic_richness), 2.0);
                cell.tfs[1] = TranscriptionFactor.init(@intFromEnum(Gene.syncopation), 1.5);
                cell.tfs[2] = TranscriptionFactor.init(@intFromEnum(Gene.polyphony_preference), 1.8);
                cell.tf_count = 3;
            },
            .bass => {
                cell.tfs[0] = TranscriptionFactor.init(@intFromEnum(Gene.groove_swing), 2.0);
                cell.tfs[1] = TranscriptionFactor.init(@intFromEnum(Gene.density), 1.5);
                cell.tf_count = 2;
            },
            .drums => {
                cell.tfs[0] = TranscriptionFactor.init(@intFromEnum(Gene.rhythmic_complexity), 2.0);
                cell.tfs[1] = TranscriptionFactor.init(@intFromEnum(Gene.density), 1.8);
                cell.tfs[2] = TranscriptionFactor.init(@intFromEnum(Gene.dynamic_range), 1.5);
                cell.tf_count = 3;
            },
            .sax => {
                cell.tfs[0] = TranscriptionFactor.init(@intFromEnum(Gene.melodic_range), 2.0);
                cell.tfs[1] = TranscriptionFactor.init(@intFromEnum(Gene.articulation), 1.8);
                cell.tfs[2] = TranscriptionFactor.init(@intFromEnum(Gene.dissonance_tolerance), 1.5);
                cell.tf_count = 3;
            },
        }

        return cell;
    }

    pub fn receive(self: *Self, signals: *const SignalMap) void {
        var i: usize = 0;
        while (i < signals.count) : (i += 1) {
            const key = signals.entries[i].key[0..signals.entries[i].key_len];
            const val = signals.entries[i].value;
            if (self.accumulated_signals.get(key)) |existing| {
                self.accumulated_signals.set(key, existing * 0.7 + val * 0.3);
            } else {
                self.accumulated_signals.set(key, val);
            }
        }
    }

    pub fn updateTfs(self: *Self) void {
        for (0..self.tf_count) |i| {
            if (self.tfs[i].gene_index < GENOME_SIZE) {
                const epi = self.epigenetic[self.tfs[i].gene_index];
                self.tfs[i].sensitivity = self.tfs[i].sensitivity * 0.9 + epi * 0.1;
            }
        }
    }

    pub fn express(self: *Self, context: *const SharedContext) CellOutput {
        if (!self.active) return CellOutput.init();

        var output = CellOutput.init();
        const channel = self.role.defaultChannel();
        const vr = self.role.velocityRange();
        const reg = self.role.register();

        // Compute TF activation
        var activation: f64 = 0.0;
        for (self.tfs[0..self.tf_count]) |tf| {
            activation += tf.activation(&self.genome);
        }

        switch (self.role) {
            .drums => self.expressDrums(&output, context, channel, vr, activation),
            .bass => self.expressBass(&output, context, channel, vr, reg, activation),
            .piano => self.expressPiano(&output, context, channel, vr, reg, activation),
            .sax => self.expressSax(&output, context, channel, vr, reg, activation),
        }

        // Quantize if snap strictness is high
        if (self.genome[@intFromEnum(Gene.snap_strictness)] > 0.5) {
            for (output.events[0..output.event_count]) |*evt| {
                evt.quantize16th();
            }
        }

        // Output signals
        output.signals.set("energy", context.energy * activation);
        output.signals.set("density", self.genome[@intFromEnum(Gene.density)]);
        output.signals.set("syncopation", self.genome[@intFromEnum(Gene.syncopation)]);

        // Update epigenetic
        for (&self.epigenetic) |*e| {
            e.* = @min(e.* + 0.01, 1.0);
        }

        self.history_count += 1;
        if (self.history_count > 64) self.history_count = 64;

        return output;
    }

    fn velocity(_: *const Self, lo: u8, hi: u8, activation: f64, base: f64) u8 {
        const raw = @as(f64, @floatFromInt(lo)) + @as(f64, @floatFromInt(hi - lo)) * base * @min(activation, 1.0);
        return @intFromFloat(std.math.clamp(@round(raw), @as(f64, @floatFromInt(lo)), @as(f64, @floatFromInt(hi))));
    }

    fn expressDrums(self: *const Self, output: *CellOutput, ctx: *const SharedContext, channel: u8, vr: @TypeOf(CellRole.drums.velocityRange()), activation: f64) void {
        const beat_f = @as(f64, @floatFromInt(ctx.beat));
        const density = self.genome[@intFromEnum(Gene.density)];
        const sync = self.genome[@intFromEnum(Gene.syncopation)];

        // Kick on 1 and 3
        if (ctx.beat == 0 or ctx.beat == 2) {
            const vel = self.velocity(vr.lo, vr.hi, activation, 0.8);
            output.addEvent(MidiEvent.init(36, vel, 0.5, beat_f, channel));
        }

        // Hi-hat
        const hh_div: usize = if (density > 0.6) 4 else 2;
        for (0..hh_div) |i| {
            const offset = beat_f + (@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(hh_div))) * @as(f64, @floatFromInt(BEATS_PER_BAR)) / 2.0;
            if (sync > 0.5 and i % 2 == 1 and ctx.beat % 2 == 0) continue;
            const vel = self.velocity(vr.lo, vr.hi, activation, 0.5);
            output.addEvent(MidiEvent.init(42, vel, 0.25, offset, channel));
        }

        // Snare on 2 and 4
        if (ctx.beat == 1 or ctx.beat == 3) {
            const vel = self.velocity(vr.lo, vr.hi, activation, 0.9);
            output.addEvent(MidiEvent.init(38, vel, 0.5, beat_f, channel));
        }

        // Ghost notes
        const complexity = self.genome[@intFromEnum(Gene.rhythmic_complexity)];
        if (complexity > 0.5 and ctx.beat % 2 == 1) {
            const vel = self.velocity(vr.lo, vr.hi, activation, 0.3);
            output.addEvent(MidiEvent.init(38, vel, 0.25, beat_f + 0.5, channel));
        }

        // Ride for higher energy
        if (ctx.energy > 0.6) {
            const vel = self.velocity(vr.lo, vr.hi, activation, 0.4);
            output.addEvent(MidiEvent.init(51, vel, 0.5, beat_f, channel));
        }
    }

    fn expressBass(self: *const Self, output: *CellOutput, ctx: *const SharedContext, channel: u8, vr: @TypeOf(CellRole.bass.velocityRange()), reg: @TypeOf(CellRole.bass.register()), activation: f64) void {
        const beat_f = @as(f64, @floatFromInt(ctx.beat));
        const chord = ctx.chordTones();
        const density = self.genome[@intFromEnum(Gene.density)];
        const groove = self.genome[@intFromEnum(Gene.groove_swing)];

        // Root on beat 1
        if (ctx.beat == 0) {
            const note = std.math.clamp(chord[0], reg.lo, reg.hi);
            const vel = self.velocity(vr.lo, vr.hi, activation, 0.9);
            output.addEvent(MidiEvent.init(note, vel, 2.0, beat_f, channel));
        }

        // Walking bass
        if (density > 0.4 and ctx.beat > 0) {
            const scale = ctx.scaleNotes();
            for (&scale) |n| {
                if (n >= reg.lo and n <= reg.hi) {
                    const offset = beat_f + if (groove > 0.5) @as(f64, 0.1) else @as(f64, 0.0);
                    const vel = self.velocity(vr.lo, vr.hi, activation, 0.6);
                    output.addEvent(MidiEvent.init(n, vel, 0.8, offset, channel));
                    break;
                }
            }
        }

        // Approach note on beat 4
        if (ctx.beat == 3 and density > 0.3) {
            const root = chord[0];
            const approach = if (root > reg.lo) root - 1 else root + 1;
            const note = std.math.clamp(approach, reg.lo, reg.hi);
            const vel = self.velocity(vr.lo, vr.hi, activation, 0.7);
            output.addEvent(MidiEvent.init(note, vel, 0.8, beat_f + 0.5, channel));
        }
    }

    fn expressPiano(self: *const Self, output: *CellOutput, ctx: *const SharedContext, channel: u8, vr: @TypeOf(CellRole.piano.velocityRange()), reg: @TypeOf(CellRole.piano.register()), activation: f64) void {
        const beat_f = @as(f64, @floatFromInt(ctx.beat));
        const chord = ctx.chordTones();
        const harmony = self.genome[@intFromEnum(Gene.harmonic_richness)];
        const sync = self.genome[@intFromEnum(Gene.syncopation)];

        if (ctx.beat == 0 or (sync > 0.5 and ctx.beat == 2)) {
            const max_notes: usize = if (self.solo) 2 else @as(usize, @intFromFloat(harmony * 4.0)) + 1;
            const vel = self.velocity(vr.lo, vr.hi, activation, 0.7);
            const offset = if (sync > 0.6) beat_f + 0.25 else beat_f;
            const duration: f64 = if (ctx.beat == 0) 2.0 else 1.5;

            for (0..@min(ctx.chord_len, max_notes)) |i| {
                const note = std.math.clamp(chord[i] + 12, reg.lo, reg.hi);
                output.addEvent(MidiEvent.init(note, vel, duration, offset, channel));
            }
        }

        // Fills
        const poly = self.genome[@intFromEnum(Gene.polyphony_preference)];
        if (poly > 0.5 and ctx.beat == 3) {
            const scale = ctx.scaleNotes();
            for (&scale) |n| {
                if (n >= reg.lo and n <= reg.hi) {
                    const vel = self.velocity(vr.lo, vr.hi, activation, 0.5);
                    output.addEvent(MidiEvent.init(n, vel, 0.5, beat_f + 0.5, channel));
                    break;
                }
            }
        }
    }

    fn expressSax(self: *const Self, output: *CellOutput, ctx: *const SharedContext, channel: u8, vr: @TypeOf(CellRole.sax.velocityRange()), reg: @TypeOf(CellRole.sax.register()), activation: f64) void {
        if (!self.solo and ctx.energy < 0.4) return;

        const beat_f = @as(f64, @floatFromInt(ctx.beat));
        const scale = ctx.scaleNotes();

        // Find notes in range
        var notes_in_range: [MAX_SCALE]u8 = undefined;
        var nir_count: usize = 0;
        for (&scale) |n| {
            if (n >= reg.lo and n <= reg.hi) {
                notes_in_range[nir_count] = n;
                nir_count += 1;
            }
        }
        if (nir_count == 0) return;

        const articulation = self.genome[@intFromEnum(Gene.articulation)];
        const sync = self.genome[@intFromEnum(Gene.syncopation)];

        const num_notes: usize = if (self.solo) @as(usize, @intFromFloat(activation * 4.0)) + 1 else 1;
        for (0..num_notes) |i| {
            const idx = (ctx.bar * BEATS_PER_BAR + ctx.beat + i) % nir_count;
            const note = notes_in_range[idx];

            const offset = beat_f + @as(f64, @floatFromInt(i)) * 0.5 + if (sync > 0.5) @as(f64, 0.125) else @as(f64, 0.0);
            const duration: f64 = if (articulation > 0.6) 0.3 else 0.7;
            const vel = self.velocity(vr.lo, vr.hi, activation, if (self.solo) 0.8 else 0.5);

            output.addEvent(MidiEvent.init(note, vel, duration, offset, channel));
        }
    }

    pub fn reset(self: *Self) void {
        self.accumulated_signals.clear();
        self.history_count = 0;
        self.active = true;
        self.solo = false;
    }

    pub fn effectiveGene(self: *const Self, gene: Gene) f64 {
        const idx = @intFromEnum(gene);
        return self.genome[idx] * (1.0 - self.epigenetic[idx] * 0.3);
    }
};

// ── Session Phase ────────────────────────────────────────────────────

pub const SessionPhase = enum(u8) {
    head = 0,
    solo_piano = 1,
    solo_sax = 2,
    trading = 3,
    collective = 4,
    coda = 5,

    pub fn defaultBars(self: SessionPhase) usize {
        return switch (self) {
            .head => BARS_PER_PHASE,
            .solo_piano => BARS_PER_PHASE,
            .solo_sax => BARS_PER_PHASE,
            .trading => BARS_PER_PHASE * 2,
            .collective => BARS_PER_PHASE,
            .coda => 4,
        };
    }

    pub fn next(self: SessionPhase) ?SessionPhase {
        return switch (self) {
            .head => .solo_piano,
            .solo_piano => .solo_sax,
            .solo_sax => .trading,
            .trading => .collective,
            .collective => .coda,
            .coda => null,
        };
    }
};

// ── Jazz Session ─────────────────────────────────────────────────────

pub const JazzSession = struct {
    cells: [4]MusicalCell,
    context: SharedContext,
    phase: SessionPhase,
    phase_bar: usize,
    phase_bars_remaining: usize,
    tick_count: usize,
    total_outputs: usize,

    const Self = @This();

    pub fn init(key: u8, tempo: f64) Self {
        const phase = SessionPhase.head;
        return .{
            .cells = .{
                MusicalCell.init(.piano),
                MusicalCell.init(.bass),
                MusicalCell.init(.drums),
                MusicalCell.init(.sax),
            },
            .context = SharedContext.init(key, tempo),
            .phase = phase,
            .phase_bar = 0,
            .phase_bars_remaining = phase.defaultBars(),
            .tick_count = 0,
            .total_outputs = 0,
        };
    }

    pub fn withEnergy(self: Self, energy: f64) Self {
        var s = self;
        s.context.energy = std.math.clamp(energy, 0.0, 1.0);
        return s;
    }

    pub fn tick(self: *Self) [4]CellOutput {
        self.updateSoloStates();

        var all_signals = SignalMap.init();
        all_signals.set("energy", self.context.energy);
        all_signals.set("beat", @floatFromInt(self.context.beat));
        all_signals.set("bar", @floatFromInt(self.context.bar));

        for (&self.cells) |*cell| {
            cell.receive(&all_signals);
            cell.updateTfs();
        }

        var outputs: [4]CellOutput = undefined;
        for (&self.cells, 0..) |*cell, i| {
            outputs[i] = cell.express(&self.context);
            // Merge signals
            for (0..outputs[i].signals.count) |j| {
                all_signals.set(outputs[i].signals.entries[j].key[0..outputs[i].signals.entries[j].key_len], outputs[i].signals.entries[j].value);
            }
        }

        self.context.tick();

        if (self.context.beat == 0 and self.tick_count > 0) {
            self.phase_bar += 1;
            self.phase_bars_remaining = self.phase_bars_remaining -| 1;
            if (self.phase_bars_remaining == 0) {
                self.advancePhase();
            }
        }

        self.modulateEnergy();
        self.tick_count += 1;
        self.total_outputs += 4;
        return outputs;
    }

    pub fn perform(self: *Self, bars: usize) usize {
        const total_beats = bars * BEATS_PER_BAR;
        for (0..total_beats) |_| {
            _ = self.tick();
        }
        return self.tick_count;
    }

    fn updateSoloStates(self: *Self) void {
        for (&self.cells) |*cell| {
            cell.solo = false;
        }

        switch (self.phase) {
            .head => {},
            .solo_piano => {
                self.cells[0].solo = true;
            },
            .solo_sax => {
                self.cells[3].solo = true;
            },
            .trading => {
                const segment = (self.phase_bar / 4) % 2;
                if (segment == 0) {
                    self.cells[0].solo = true;
                } else {
                    self.cells[3].solo = true;
                }
            },
            .collective => {},
            .coda => {},
        }
    }

    fn advancePhase(self: *Self) void {
        if (self.phase.next()) |next| {
            self.phase = next;
            self.phase_bar = 0;
            self.phase_bars_remaining = next.defaultBars();
        }
    }

    fn modulateEnergy(self: *Self) void {
        const target: f64 = switch (self.phase) {
            .head => 0.5,
            .solo_piano => 0.6,
            .solo_sax => 0.8,
            .trading => 0.7 + 0.2 * @sin(@as(f64, @floatFromInt(self.phase_bar)) / 8.0),
            .collective => 0.9,
            .coda => 0.3 * @max(1.0 - @as(f64, @floatFromInt(self.phase_bar)) / 4.0, 0.0),
        };
        self.context.energy = self.context.energy * 0.9 + target * 0.1;
    }

    pub fn isFinished(self: *const Self) bool {
        return self.phase == .coda and self.phase_bars_remaining == 0;
    }

    pub fn totalBars(self: *const Self) usize {
        return self.tick_count / BEATS_PER_BAR;
    }
};

// ── Trading Fours ────────────────────────────────────────────────────

pub const TradingFours = struct {
    cell_a: CellRole,
    cell_b: CellRole,
    bars_per_trade: usize,
    current_bar: usize,
    current_leader: CellRole,

    pub fn init(cell_a: CellRole, cell_b: CellRole) TradingFours {
        return .{
            .cell_a = cell_a,
            .cell_b = cell_b,
            .bars_per_trade = 4,
            .current_bar = 0,
            .current_leader = cell_a,
        };
    }

    pub fn advanceBar(self: *TradingFours) CellRole {
        self.current_bar += 1;
        if (self.current_bar >= self.bars_per_trade) {
            self.current_bar = 0;
            self.current_leader = if (self.current_leader == self.cell_a) self.cell_b else self.cell_a;
        }
        return self.current_leader;
    }

    pub fn isLeading(self: *const TradingFours, role: CellRole) bool {
        return self.current_leader == role;
    }

    pub fn responder(self: *const TradingFours) CellRole {
        return if (self.current_leader == self.cell_a) self.cell_b else self.cell_a;
    }
};

// ── Call and Response ────────────────────────────────────────────────

pub const CallAndResponse = struct {
    leader: CellRole,
    responder_role: CellRole,
    call_beats: usize,
    response_beats: usize,
    current_position: usize,
    in_call: bool,

    pub fn init(leader: CellRole, responder_role: CellRole) CallAndResponse {
        return .{
            .leader = leader,
            .responder_role = responder_role,
            .call_beats = 4,
            .response_beats = 4,
            .current_position = 0,
            .in_call = true,
        };
    }

    pub fn tick(self: *CallAndResponse) CellRole {
        const active = if (self.in_call) self.leader else self.responder_role;
        self.current_position += 1;

        if (self.in_call and self.current_position >= self.call_beats) {
            self.in_call = false;
            self.current_position = 0;
        } else if (!self.in_call and self.current_position >= self.response_beats) {
            self.in_call = true;
            self.current_position = 0;
        }

        return active;
    }

    pub fn isCall(self: *const CallAndResponse) bool {
        return self.in_call;
    }

    pub fn withDurations(self: CallAndResponse, call: usize, response: usize) CallAndResponse {
        var cr = self;
        cr.call_beats = call;
        cr.response_beats = response;
        return cr;
    }
};

// ── Vamp ─────────────────────────────────────────────────────────────

pub const Vamp = struct {
    role: CellRole,
    pattern: [MAX_EVENTS]MidiEvent,
    pattern_len: usize,
    repetitions: usize,
    current_bar: usize,
    active: bool,

    pub fn init(role: CellRole, pattern: []const MidiEvent, repetitions: usize) Vamp {
        var v = Vamp{
            .role = role,
            .pattern = undefined,
            .pattern_len = @min(pattern.len, MAX_EVENTS),
            .repetitions = repetitions,
            .current_bar = 0,
            .active = true,
        };
        @memcpy(v.pattern[0..v.pattern_len], pattern[0..v.pattern_len]);
        return v;
    }

    pub fn pianoVamp(key: u8, repetitions: usize) Vamp {
        const pattern = [_]MidiEvent{
            MidiEvent.init(key + 48, 80, 1.0, 0.0, 0),
            MidiEvent.init(key + 52, 70, 1.0, 0.0, 0),
            MidiEvent.init(key + 55, 70, 1.0, 0.0, 0),
            MidiEvent.init(key + 48, 60, 0.5, 2.0, 0),
            MidiEvent.init(key + 52, 60, 0.5, 2.0, 0),
            MidiEvent.init(key + 55, 60, 0.5, 2.0, 0),
        };
        return init(.piano, &pattern, repetitions);
    }

    pub fn currentEvents(self: *const Vamp) []const MidiEvent {
        return self.pattern[0..self.pattern_len];
    }

    pub fn advance(self: *Vamp) bool {
        self.current_bar += 1;
        if (self.current_bar >= self.repetitions) {
            self.active = false;
            return false;
        }
        return true;
    }

    pub fn reset(self: *Vamp) void {
        self.current_bar = 0;
        self.active = true;
    }

    pub fn remaining(self: *const Vamp) usize {
        return self.repetitions -| self.current_bar;
    }
};

// ── Tests ────────────────────────────────────────────────────────────

test "musical cell init piano" {
    const cell = MusicalCell.init(.piano);
    try testing.expect(cell.role == .piano);
    try testing.expect(cell.active);
    try testing.expect(!cell.solo);
    try testing.expect(cell.history_count == 0);
    try testing.expect(cell.tf_count == 3);
}

test "musical cell role genomes differ" {
    const piano = MusicalCell.init(.piano);
    const drums = MusicalCell.init(.drums);
    // Different density values
    try testing.expect(piano.genome[@intFromEnum(Gene.density)] != drums.genome[@intFromEnum(Gene.density)]);
}

test "cell receive signals" {
    var cell = MusicalCell.init(.bass);
    var signals = SignalMap.init();
    signals.set("energy", 0.8);
    cell.receive(&signals);
    const val = cell.accumulated_signals.get("energy");
    try testing.expect(val != null);
    try testing.expect(val.? > 0.0);
}

test "cell update tfs" {
    var cell = MusicalCell.init(.sax);
    _ = cell.tfs[0].sensitivity;
    cell.updateTfs();
    // Structure preserved
    try testing.expect(cell.tf_count == 3);
}

test "cell express inactive" {
    var cell = MusicalCell.init(.piano);
    cell.active = false;
    const ctx = SharedContext.init(60, 120.0);
    const output = cell.express(&ctx);
    try testing.expect(output.isEmpty());
}

test "cell express drums" {
    var cell = MusicalCell.init(.drums);
    const ctx = SharedContext.init(60, 120.0);
    const output = cell.express(&ctx);
    try testing.expect(!output.isEmpty());
}

test "cell express all roles" {
    inline for (&[_]CellRole{ .piano, .bass, .drums, .sax }) |role| {
        var cell = MusicalCell.init(role);
        const ctx = SharedContext.init(60, 120.0);
        const output = cell.express(&ctx);
        if (role == .sax) continue; // might rest at low energy
        try testing.expect(!output.isEmpty());
    }
}

test "cell history accumulates" {
    var cell = MusicalCell.init(.piano);
    const ctx = SharedContext.init(60, 120.0);
    _ = cell.express(&ctx);
    try testing.expect(cell.history_count == 1);
    _ = cell.express(&ctx);
    try testing.expect(cell.history_count == 2);
}

test "cell effective gene" {
    const cell = MusicalCell.init(.piano);
    const raw = cell.genome[@intFromEnum(Gene.syncopation)];
    const effective = cell.effectiveGene(.syncopation);
    try testing.expect(effective <= raw + 0.001);
}

test "jazz session init" {
    const session = JazzSession.init(60, 140.0);
    try testing.expect(session.phase == .head);
    try testing.expect(session.context.key == 60);
    try testing.expect(session.context.tempo == 140.0);
    try testing.expect(session.tick_count == 0);
}

test "jazz session tick" {
    var session = JazzSession.init(60, 120.0);
    _ = session.tick();
    try testing.expect(session.tick_count == 1);
}

test "jazz session perform" {
    var session = JazzSession.init(60, 120.0);
    const ticks = session.perform(4);
    try testing.expect(ticks == 16);
}

test "jazz session phase advances" {
    var session = JazzSession.init(60, 120.0);
    for (0..32) |_| {
        _ = session.tick();
    }
    try testing.expect(session.phase != .head);
}

test "jazz session solo piano phase" {
    var session = JazzSession.init(60, 120.0);
    session.phase = .solo_piano;
    session.updateSoloStates();
    try testing.expect(session.cells[0].solo); // piano
    try testing.expect(!session.cells[3].solo); // sax
}

test "jazz session solo sax phase" {
    var session = JazzSession.init(60, 120.0);
    session.phase = .solo_sax;
    session.updateSoloStates();
    try testing.expect(session.cells[3].solo); // sax
    try testing.expect(!session.cells[0].solo); // piano
}

test "jazz session trading phase" {
    var session = JazzSession.init(60, 120.0);
    session.phase = .trading;
    session.phase_bar = 0;
    session.updateSoloStates();
    try testing.expect(session.cells[0].solo); // piano leads first

    session.phase_bar = 4;
    session.updateSoloStates();
    try testing.expect(session.cells[3].solo); // sax leads next
}

test "jazz session is finished" {
    var session = JazzSession.init(60, 120.0);
    try testing.expect(!session.isFinished());
    session.phase = .coda;
    session.phase_bars_remaining = 0;
    try testing.expect(session.isFinished());
}

test "trading fours alternation" {
    var tf = TradingFours.init(.piano, .sax);
    try testing.expect(tf.current_leader == .piano);
    for (0..4) |_| {
        _ = tf.advanceBar();
    }
    try testing.expect(tf.current_leader == .sax);
    for (0..4) |_| {
        _ = tf.advanceBar();
    }
    try testing.expect(tf.current_leader == .piano);
}

test "trading fours is leading" {
    const tf = TradingFours.init(.piano, .sax);
    try testing.expect(tf.isLeading(.piano));
    try testing.expect(!tf.isLeading(.sax));
    try testing.expect(tf.responder() == .sax);
}

test "call and response" {
    var cr = CallAndResponse.init(.sax, .piano);
    try testing.expect(cr.isCall());
    for (0..4) |_| {
        try testing.expect(cr.tick() == .sax);
    }
    try testing.expect(!cr.isCall());
    for (0..4) |_| {
        try testing.expect(cr.tick() == .piano);
    }
    try testing.expect(cr.isCall());
}

test "call and response custom durations" {
    const cr = CallAndResponse.init(.sax, .piano).withDurations(2, 2);
    try testing.expect(cr.call_beats == 2);
    try testing.expect(cr.response_beats == 2);
}

test "vamp creation" {
    const vamp = Vamp.pianoVamp(60, 8);
    try testing.expect(vamp.role == .piano);
    try testing.expect(vamp.repetitions == 8);
    try testing.expect(vamp.active);
    try testing.expect(vamp.pattern_len == 6);
}

test "vamp advance" {
    var vamp = Vamp.pianoVamp(60, 3);
    try testing.expect(vamp.advance());
    try testing.expect(vamp.advance());
    try testing.expect(!vamp.advance());
    try testing.expect(!vamp.active);
}

test "vamp reset" {
    var vamp = Vamp.pianoVamp(60, 2);
    _ = vamp.advance();
    _ = vamp.advance();
    try testing.expect(!vamp.active);
    vamp.reset();
    try testing.expect(vamp.active);
    try testing.expect(vamp.current_bar == 0);
}

test "vamp remaining" {
    var vamp = Vamp.pianoVamp(60, 4);
    try testing.expect(vamp.remaining() == 4);
    _ = vamp.advance();
    try testing.expect(vamp.remaining() == 3);
}

test "midi event quantize" {
    var evt = MidiEvent.init(60, 80, 0.37, 1.13, 0);
    evt.quantize16th();
    try testing.expectApproxEqAbs(@as(f64, 1.25), evt.offset_beats, 1e-10);
}

test "shared context tick" {
    var ctx = SharedContext.init(60, 120.0);
    try testing.expect(ctx.beat == 0);
    ctx.tick();
    try testing.expect(ctx.beat == 1);
    try testing.expect(ctx.bar == 0);
    ctx.tick();
    ctx.tick();
    ctx.tick();
    try testing.expect(ctx.beat == 0);
    try testing.expect(ctx.bar == 1);
}

test "shared context scale notes" {
    const ctx = SharedContext.init(60, 120.0);
    const notes = ctx.scaleNotes();
    try testing.expect(notes[0] == 60); // C
    try testing.expect(notes[2] == 64); // E
    try testing.expect(notes[4] == 67); // G
}

test "session phase sequence" {
    var phase: ?SessionPhase = .head;
    var count: usize = 0;
    while (phase != null) : (count += 1) {
        phase = phase.?.next();
    }
    try testing.expect(count == 6);
}

test "cell reset" {
    var cell = MusicalCell.init(.piano);
    const ctx = SharedContext.init(60, 120.0);
    _ = cell.express(&ctx);
    cell.solo = true;
    cell.active = false;
    cell.reset();
    try testing.expect(cell.history_count == 0);
    try testing.expect(cell.active);
    try testing.expect(!cell.solo);
}

test "transcription factor activation" {
    const tf = TranscriptionFactor.init(0, 2.0);
    const genome = [1]f64{0.5} ** GENOME_SIZE;
    const act = tf.activation(&genome);
    try testing.expect(act > 0.0);
    try testing.expect(act < 1.0);
}

test "jazz session with energy" {
    const session = JazzSession.init(60, 120.0).withEnergy(0.9);
    try testing.expectApproxEqAbs(@as(f64, 0.9), session.context.energy, 1e-10);
}

test "signal map set get" {
    var sm = SignalMap.init();
    sm.set("test", 0.5);
    const val = sm.get("test");
    try testing.expect(val != null);
    try testing.expectApproxEqAbs(@as(f64, 0.5), val.?, 1e-10);
}

test "signal map update existing" {
    var sm = SignalMap.init();
    sm.set("x", 1.0);
    sm.set("x", 2.0);
    try testing.expect(sm.count == 1);
    try testing.expectApproxEqAbs(@as(f64, 2.0), sm.get("x").?, 1e-10);
}
