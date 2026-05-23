/*
 * world_music.h — Single-header library for world music scales, tuning systems,
 * ornaments, rhythms, musical cohomology, and Penrose music generation.
 *
 * Usage:
 *   In exactly ONE .c file, do:
 *     #define WORLD_MUSIC_IMPLEMENTATION
 *     #include "world_music.h"
 *   In all other files, just:
 *     #include "world_music.h"
 *
 * License: MIT
 */

#ifndef WORLD_MUSIC_H
#define WORLD_MUSIC_H

#include <math.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <assert.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── Constants ────────────────────────────────────────────────────── */

#define WM_PHI          1.618033988749895
#define WM_INV_PHI      0.618033988749895
#define WM_PI           3.14159265358979323846
#define WM_TWO_PI       6.283185307179586
#define WM_MAX_NOTES    12
#define WM_MAX_HITS     32
#define WM_MAX_SHRUTI   22
#define WM_NUM_SCALES   36
#define WM_NUM_RHYTHMS  26

/* ── Scales ───────────────────────────────────────────────────────── */

typedef struct {
    const char* name;
    const char* culture;
    int notes[WM_MAX_NOTES];
    int note_count;
    float vadi;      /* -1 if not applicable */
    float samvadi;   /* -1 if not applicable */
    const char* rasa; /* NULL if not applicable */
} WorldScale;

/* Look up a scale by name (case-insensitive, underscores/hyphens OK).
   Returns NULL if not found. */
const WorldScale* wm_scale(const char* name);

/* Get all scales. Sets *count to the number returned. */
const WorldScale* wm_all_scales(int* count);

/* Get scales filtered by culture. Caller must NOT free. */
const WorldScale* wm_scales_by_culture(const char* culture, int* count);

/* Expand a scale to MIDI note numbers. Returns count of notes written.
   Only whole-semitone notes (quarter-tones rounded). */
int wm_scale_to_midi(const char* name, int root, int octave_range, int* out, int out_cap);

/* ── Tuning Systems ───────────────────────────────────────────────── */

typedef double (*wm_generator_fn)(int degree);

typedef struct {
    const char* name;
    int divisions;              /* number of pitch classes */
    wm_generator_fn generator;  /* generates cents for a given degree */
} TuningSystem;

double wm_tuning_cents(const TuningSystem* sys, int degree);

/* Snap note_cents to nearest pitch in the tuning system.
   If epsilon > 0 and nearest is farther than epsilon, return note_cents unchanged. */
double wm_snap_to_tuning(double note_cents, const TuningSystem* sys, double epsilon);

/* Pre-built tuning systems — return pointers to static structs */
const TuningSystem* wm_tuning_equal_temperament(void);
const TuningSystem* wm_tuning_just_intonation(void);
const TuningSystem* wm_tuning_shruti_22(void);
const TuningSystem* wm_tuning_quarter_tone_24(void);
const TuningSystem* wm_tuning_pentatonic_5(void);
const TuningSystem* wm_tuning_meantone(void);
const TuningSystem* wm_tuning_pythagorean(void);

/* Generate all cents for a tuning system into out[]. Returns count written. */
int wm_tuning_all_cents(const TuningSystem* sys, double* out, int out_cap);

/* ── Ornaments ────────────────────────────────────────────────────── */

/* Indian meend (glide). curve: 0=exponential, 1=logarithmic, 2=linear.
   Writes steps+1 values to out[]. */
void wm_ornament_meend(double start, double end, int steps, int curve, double* out);

/* Indian gamak (oscillation). Returns total_points+1 values.
   Caller must allocate at least (int)(speed*cycles*4 + 1) doubles. */
int wm_ornament_gamak(double center, double amplitude, double speed, int cycles, double* out);

/* Arabic quarter-tone bend. Writes 2*steps+5 values. */
int wm_ornament_quarter_bend(double note, int direction, double cents, int steps, double* out);

/* Jazz shake. Writes points values. Returns points. */
int wm_ornament_shakes(double note, double speed, double amplitude, double* out, int out_cap);

/* ── Rhythms ──────────────────────────────────────────────────────── */

typedef struct {
    const char* name;
    const char* culture;
    int subdivisions;
    int hits[WM_MAX_HITS];
    int hit_count;
} RhythmPattern;

/* Look up a rhythm pattern by name. Returns NULL if not found. */
const RhythmPattern* wm_rhythm(const char* name);

/* Get all rhythm patterns. Sets *count. */
const RhythmPattern* wm_all_rhythms(int* count);

/* ── Musical Cohomology ───────────────────────────────────────────── */

typedef struct {
    int h0;                  /* number of connected components */
    int h1;                  /* number of independent cycles (holes) */
    int emergence_detected;  /* 1 if h1 > 0 */
} CohomologyResult;

/* Compute simplicial cohomology on a chord progression.
   chords: array of chord root notes (MIDI), n_chords elements.
   transitions: pairs (from, to) as flat array, n_transitions*2 elements.
   Returns H0, H1, and emergence flag. */
CohomologyResult wm_musical_cohomology(
    const int* chords, int n_chords,
    const int* transitions, int n_transitions
);

/* ── Penrose Music ────────────────────────────────────────────────── */

/* Generate Penrose rhythm hits via cut-and-project.
   range: lattice scan range (try 3-6)
   groove_width: acceptance window half-width (try 0.3-0.8)
   hits: output hit positions (time indices)
   n_hits: set to the number of hits written */
void wm_penrose_rhythm(int range, double groove_width, int* hits, int* n_hits);

/* Generate Penrose melody notes from a scale.
   scale: array of scale degrees (semitones)
   scale_len: length of scale array
   range: lattice scan range
   notes: output MIDI note numbers
   n_notes: set to count written */
void wm_penrose_melody(const int* scale, int scale_len, int range,
                       int* notes, int* n_notes);

/* ── Utility ──────────────────────────────────────────────────────── */

/* Ratio to cents conversion */
double wm_ratio_to_cents(double ratio);

/* Compare two doubles for approximate equality */
int wm_approx_eq(double a, double b, double epsilon);

#ifdef __cplusplus
}
#endif

#endif /* WORLD_MUSIC_H */

/* ═════════════════════════════════════════════════════════════════════
 * IMPLEMENTATION
 * ═════════════════════════════════════════════════════════════════════ */
#ifdef WORLD_MUSIC_IMPLEMENTATION

/* ── Internal helpers ─────────────────────────────────────────────── */

static double wm__ratio_to_cents_impl(double ratio) {
    return 1200.0 * log2(ratio);
}

static int wm__strieq(const char* a, const char* b) {
    if (!a || !b) return 0;
    while (*a && *b) {
        char ca = *a, cb = *b;
        if (ca >= 'A' && ca <= 'Z') ca += 32;
        if (cb >= 'A' && cb <= 'Z') cb += 32;
        /* treat '-' and '_' and ' ' as equivalent */
        if ((ca == '-' || ca == '_' || ca == ' ') && (cb == '-' || cb == '_' || cb == ' ')) {
            a++; b++; continue;
        }
        if (ca != cb) return 0;
        a++; b++;
    }
    /* skip trailing separators */
    while (*a && (*a == '-' || *a == '_' || *a == ' ')) a++;
    while (*b && (*b == '-' || *b == '_' || *b == ' ')) b++;
    return *a == *b;
}

/* ── Scale data ───────────────────────────────────────────────────── */

static WorldScale wm__scales[] = {
    /* Indian Ragas (10) */
    {"bhairavi",    "indian",   {0,1,3,5,7,8,10},       7,  1,    5,    "devotional"},
    {"yaman",       "indian",   {0,2,4,6,7,9,11},       7,  0,    4,    "romantic"},
    {"darbari",     "indian",   {0,2,3,5,7,8,10},       7,  3,    7,    "solemn"},
    {"malkauns",    "indian",   {0,2,4,6,8,10},          6,  2,    6,    "meditative"},
    {"bageshri",    "indian",   {0,2,3,5,7,9,10},       7,  2,    7,    "longing"},
    {"todi",        "indian",   {0,1,3,5,7,8,11},       7,  3,    7,    "pathos"},
    {"bhairav",     "indian",   {0,1,4,5,7,8,11},       7,  4,    8,    "solemn"},
    {"kafi",        "indian",   {0,2,3,5,7,9,10},       7,  3,    7,    "playful"},
    {"bilawal",     "indian",   {0,2,4,5,7,9,11},       7,  4,    0,    "joyful"},
    {"asavari",     "indian",   {0,2,3,5,7,8,10},       7,  3,    7,    "melancholy"},

    /* Arabic / Turkish Maqamat (10) */
    {"rast",        "arabic",   {0,2,4,5,7,9,11},       7,  -1,  -1,   NULL},
    {"bayati",      "arabic",   {0,2,4,5,7,9,10},       7,  -1,  -1,   NULL},  /* rounded from [0,1.5,4,5,7,8.5,10] */
    {"hijaz",       "arabic",   {0,1,4,5,7,8,11},       7,  -1,  -1,   NULL},
    {"sikah",       "arabic",   {0,2,4,5,7,9,11},       7,  -1,  -1,   NULL},  /* rounded from [0,2,3.5,5,7,8.5,10.5] */
    {"nahawand",    "arabic",   {0,2,3,5,7,8,11},       7,  -1,  -1,   NULL},
    {"kurd",        "arabic",   {0,1,3,5,7,8,10},       7,  -1,  -1,   NULL},
    {"ajam",        "arabic",   {0,2,4,5,7,9,11},       7,  -1,  -1,   NULL},
    {"saba",        "arabic",   {0,1,3,4,6,7,10},       7,  -1,  -1,   NULL},
    {"huzam",       "arabic",   {0,2,4,5,7,9,10},       7,  -1,  -1,   NULL},  /* rounded from [0,2,3.5,5,7,8.5,10] */
    {"nakriz",      "arabic",   {0,2,3,5,7,8,11},       7,  -1,  -1,   NULL},

    /* East Asian Pentatonic (10) */
    {"in_scale",        "japanese",     {0,2,3,7,8},        5, -1, -1, NULL},
    {"yo_scale",        "japanese",     {0,2,5,7,9},        5, -1, -1, NULL},
    {"hirajoshi",       "japanese",     {0,2,3,7,8},        5, -1, -1, NULL},
    {"kumoi",           "japanese",     {0,2,3,7,9},        5, -1, -1, NULL},
    {"gong_mode",       "chinese",      {0,2,4,7,9},        5, -1, -1, NULL},
    {"shang_mode",      "chinese",      {0,2,4,7,9},        5, -1, -1, NULL},
    {"jiao_mode",       "chinese",      {0,2,5,7,10},       5, -1, -1, NULL},
    {"zhi_mode",        "chinese",      {0,2,5,7,10},       5, -1, -1, NULL},
    {"yu_mode",         "chinese",      {0,3,5,7,10},       5, -1, -1, NULL},
    {"pentatonic_major","east_asian",   {0,2,4,7,9},        5, -1, -1, NULL},

    /* African Scales (6) */
    {"ewe_standard",    "ewe",          {0,2,4,5,7,9,11},   7, -1, -1, NULL},
    {"pentatonic_african","african",    {0,2,3,7,8},        5, -1, -1, NULL},
    {"zimbabwe_mbira",  "shona",        {0,3,5,7,8,10},     6, -1, -1, NULL},
    {"amadinda_scale",  "buganda",      {0,2,4,5,7,9},      6, -1, -1, NULL},
    {"manden_scale",    "manden",       {0,2,4,6,7,9,11},   7, -1, -1, NULL},
    {"tigre_scale",     "tigre",        {0,1,3,5,7,8,10},   7, -1, -1, NULL},
};

#define WM__SCALE_COUNT (sizeof(wm__scales) / sizeof(wm__scales[0]))

const WorldScale* wm_scale(const char* name) {
    for (int i = 0; i < (int)WM__SCALE_COUNT; i++) {
        if (wm__strieq(name, wm__scales[i].name)) return &wm__scales[i];
    }
    return NULL;
}

const WorldScale* wm_all_scales(int* count) {
    *count = (int)WM__SCALE_COUNT;
    return wm__scales;
}

const WorldScale* wm_scales_by_culture(const char* culture, int* count) {
    static const WorldScale* filtered[WM_NUM_SCALES];
    int n = 0;
    for (int i = 0; i < (int)WM__SCALE_COUNT; i++) {
        if (wm__strieq(culture, wm__scales[i].culture)) {
            filtered[n++] = &wm__scales[i];
        }
    }
    *count = n;
    return filtered[0]; /* contiguous in the static array for same culture */
}

int wm_scale_to_midi(const char* name, int root, int octave_range, int* out, int out_cap) {
    const WorldScale* s = wm_scale(name);
    if (!s) return 0;
    int count = 0;
    for (int oct = 0; oct < octave_range && count < out_cap; oct++) {
        for (int n = 0; n < s->note_count && count < out_cap; n++) {
            int midi = root + s->notes[n] + oct * 12;
            if (midi >= 0 && midi <= 127) {
                /* deduplicate */
                int dup = 0;
                for (int j = 0; j < count; j++) {
                    if (out[j] == midi) { dup = 1; break; }
                }
                if (!dup) out[count++] = midi;
            }
        }
    }
    /* sort */
    for (int i = 0; i < count - 1; i++)
        for (int j = i + 1; j < count; j++)
            if (out[i] > out[j]) { int t = out[i]; out[i] = out[j]; out[j] = t; }
    return count;
}

/* ── Tuning Systems ───────────────────────────────────────────────── */



static double wm__gen_equal_12(int degree) { return degree * (1200.0 / 12.0); }
static double wm__gen_just(int degree) {
    static const double ratios[] = {1, 16.0/15, 9.0/8, 6.0/5, 5.0/4, 4.0/3, 45.0/32, 3.0/2, 8.0/5, 5.0/3, 9.0/5, 15.0/8};
    if (degree < 0 || degree >= 12) return 0.0;
    return wm__ratio_to_cents_impl(ratios[degree]);
}
static double wm__gen_shruti(int degree) {
    static const double ratios[] = {
        1, 256.0/243, 16.0/15, 10.0/9, 9.0/8, 32.0/27, 6.0/5, 5.0/4, 81.0/64,
        4.0/3, 27.0/20, 45.0/32, 729.0/512, 3.0/2, 128.0/81, 8.0/5, 5.0/3,
        27.0/16, 16.0/9, 9.0/5, 15.0/8, 243.0/128
    };
    if (degree < 0 || degree >= 22) return 0.0;
    return wm__ratio_to_cents_impl(ratios[degree]);
}
static double wm__gen_quarter_24(int degree) { return degree * 50.0; }
static double wm__gen_penta_5(int degree) { return degree * 240.0; }
static double wm__gen_meantone(int degree) {
    static double notes[12] = {0};
    static int computed = 0;
    if (!computed) {
        double fifth = 1200.0 * log2(pow(5.0, 0.25));
        double acc = 0.0;
        notes[0] = 0.0;
        for (int i = 1; i < 12; i++) {
            acc += fifth;
            acc = fmod(acc, 1200.0);
            notes[i] = acc;
        }
        /* sort */
        for (int i = 0; i < 11; i++)
            for (int j = i+1; j < 12; j++)
                if (notes[i] > notes[j]) { double t = notes[i]; notes[i] = notes[j]; notes[j] = t; }
        computed = 1;
    }
    if (degree < 0 || degree >= 12) return 0.0;
    return notes[degree];
}
static double wm__gen_pythagorean(int degree) {
    static double notes[12] = {0};
    static int computed = 0;
    if (!computed) {
        double fifth = 1200.0 * log2(3.0 / 2.0);
        double acc = 0.0;
        notes[0] = 0.0;
        for (int i = 1; i < 12; i++) {
            acc += fifth;
            acc = fmod(acc, 1200.0);
            notes[i] = acc;
        }
        for (int i = 0; i < 11; i++)
            for (int j = i+1; j < 12; j++)
                if (notes[i] > notes[j]) { double t = notes[i]; notes[i] = notes[j]; notes[j] = t; }
        computed = 1;
    }
    if (degree < 0 || degree >= 12) return 0.0;
    return notes[degree];
}

static TuningSystem wm__tunings[] = {
    {"equal_temperament",   12, wm__gen_equal_12},
    {"just_intonation",     12, wm__gen_just},
    {"shruti_22",           22, wm__gen_shruti},
    {"quarter_tone_24",     24, wm__gen_quarter_24},
    {"pentatonic_5",         5, wm__gen_penta_5},
    {"meantone",            12, wm__gen_meantone},
    {"pythagorean",         12, wm__gen_pythagorean},
};

const TuningSystem* wm_tuning_equal_temperament(void)  { return &wm__tunings[0]; }
const TuningSystem* wm_tuning_just_intonation(void)     { return &wm__tunings[1]; }
const TuningSystem* wm_tuning_shruti_22(void)           { return &wm__tunings[2]; }
const TuningSystem* wm_tuning_quarter_tone_24(void)     { return &wm__tunings[3]; }
const TuningSystem* wm_tuning_pentatonic_5(void)        { return &wm__tunings[4]; }
const TuningSystem* wm_tuning_meantone(void)            { return &wm__tunings[5]; }
const TuningSystem* wm_tuning_pythagorean(void)         { return &wm__tunings[6]; }

double wm_tuning_cents(const TuningSystem* sys, int degree) {
    if (!sys || !sys->generator) return 0.0;
    return sys->generator(degree);
}

int wm_tuning_all_cents(const TuningSystem* sys, double* out, int out_cap) {
    if (!sys) return 0;
    int n = sys->divisions < out_cap ? sys->divisions : out_cap;
    for (int i = 0; i < n; i++) out[i] = sys->generator(i);
    return n;
}

double wm_snap_to_tuning(double note_cents, const TuningSystem* sys, double epsilon) {
    if (!sys) return note_cents;
    double best_dist = 1e18;
    double best_val = 0.0;
    for (int i = 0; i < sys->divisions; i++) {
        double c = sys->generator(i);
        double nc = fmod(note_cents, 1200.0);
        double cc = fmod(c, 1200.0);
        double diff = fabs(cc - nc);
        if (diff > 600.0) diff = 1200.0 - diff;
        if (diff < best_dist) {
            best_dist = diff;
            best_val = cc;
        }
    }
    if (epsilon > 0 && best_dist > epsilon) return note_cents;
    return best_val;
}

/* ── Ornaments ────────────────────────────────────────────────────── */

void wm_ornament_meend(double start, double end, int steps, int curve, double* out) {
    if (steps < 1) { out[0] = start; return; }
    for (int i = 0; i <= steps; i++) {
        double t = (double)i / steps;
        double value;
        if (curve == 0)       value = start + (end - start) * (t * t);
        else if (curve == 1)  value = start + (end - start) * (1.0 - (1.0 - t) * (1.0 - t));
        else                  value = start + (end - start) * t;
        out[i] = round(value * 10000.0) / 10000.0;
    }
}

int wm_ornament_gamak(double center, double amplitude, double speed, int cycles, double* out) {
    int total_points = (int)(speed * cycles * 4);
    for (int i = 0; i <= total_points; i++) {
        double t = (double)i / (total_points > 0 ? total_points : 1);
        double decay = 1.0 - t * 0.3;
        double val = center + amplitude * decay * sin(2.0 * WM_PI * speed * cycles * t);
        out[i] = round(val * 10000.0) / 10000.0;
    }
    return total_points + 1;
}

int wm_ornament_quarter_bend(double note, int direction, double cents, int steps, double* out) {
    double semitones = cents / 100.0;
    double target = (direction == 0) ? note + semitones : note - semitones;
    int idx = 0;
    /* smoothstep up */
    for (int i = 0; i <= steps; i++) {
        double t = (double)i / steps;
        double val = t * t * (3.0 - 2.0 * t);
        out[idx++] = round((note + (target - note) * val) * 10000.0) / 10000.0;
    }
    /* hold */
    for (int i = 0; i < 4; i++) out[idx++] = round(target * 10000.0) / 10000.0;
    /* smoothstep down */
    for (int i = 0; i <= steps; i++) {
        double t = (double)i / steps;
        double val = t * t * (3.0 - 2.0 * t);
        out[idx++] = round((target + (note - target) * val) * 10000.0) / 10000.0;
    }
    return idx;
}

int wm_ornament_shakes(double note, double speed, double amplitude, double* out, int out_cap) {
    int points = (int)(speed * 8);
    if (points > out_cap) points = out_cap;
    for (int i = 0; i < points; i++) {
        double t = (double)i / (points - 1 > 0 ? points - 1 : 1);
        double val = note + amplitude * sin(2.0 * WM_PI * speed * t);
        out[i] = round(val * 10000.0) / 10000.0;
    }
    return points;
}

/* ── Rhythm data ──────────────────────────────────────────────────── */

static RhythmPattern wm__rhythms[] = {
    /* Clave patterns (5) */
    {"son_2_3",        "cuban",       16, {0,3,6,8,11},               5},
    {"son_3_2",        "cuban",       16, {0,3,6,10,13},              5},
    {"rumba_2_3",      "cuban",       16, {0,3,6,8,12},               5},
    {"rumba_3_2",      "cuban",       16, {0,4,8,10,13},              5},
    {"bossa_nova",     "brazilian",   16, {0,3,6,8,11,14},            6},

    /* Bell patterns (6) */
    {"agbadza",        "ewe",         12, {0,3,4,6,8,10},             6},
    {"gahu",           "ewe",         12, {0,2,5,6,8,10},             6},
    {"atsiagbekor",    "ewe",         12, {0,2,5,6,8,11},             6},
    {"kinka",          "ewe",         12, {0,3,6,8,11},               5},
    {"yanvalou",       "west_africa", 16, {0,3,6,9,12,15},            6},
    {"iren",           "west_africa", 16, {0,2,4,6,8,10,12,14},       8},

    /* Indian talas (7) */
    {"teental",        "indian",      16, {0,4,8,12},                 4},
    {"jhap_tal",       "indian",      10, {0,2,5,7},                  4},
    {"rupak",          "indian",       7, {0,3,5},                    3},
    {"ek_tal",         "indian",      12, {0,2,4,6,8,10},             6},
    {"kaharwa",        "indian",       8, {0,4},                      2},
    {"dadra",          "indian",       6, {0,3},                      2},
    {"deepchandi",     "indian",      14, {0,3,7,10},                 4},

    /* Arabic iqa'at (8) */
    {"maqsum",         "arabic",       8, {0,2,4,6},                  4},
    {"baladi",         "arabic",       8, {0,2,4,6},                  4},
    {"saidi",          "arabic",       8, {0,2,4,6},                  4},
    {"malfuf",         "arabic",       4, {0,2},                      2},
    {"fallahi",        "arabic",       4, {0,2},                      2},
    {"sama_i_thaqil",  "arabic",      20, {0,4,8,12,16},              5},
    {"aqsaq",          "arabic",      18, {0,4,8,12,16},              5},
    {"dawr_hind",      "arabic",      14, {0,4,8,12},                 4},
};

#define WM__RHYTHM_COUNT (sizeof(wm__rhythms) / sizeof(wm__rhythms[0]))

const RhythmPattern* wm_rhythm(const char* name) {
    for (int i = 0; i < (int)WM__RHYTHM_COUNT; i++) {
        if (wm__strieq(name, wm__rhythms[i].name)) return &wm__rhythms[i];
    }
    return NULL;
}

const RhythmPattern* wm_all_rhythms(int* count) {
    *count = (int)WM__RHYTHM_COUNT;
    return wm__rhythms;
}

/* ── Musical Cohomology ───────────────────────────────────────────── */

CohomologyResult wm_musical_cohomology(
    const int* chords, int n_chords,
    const int* transitions, int n_transitions
) {
    CohomologyResult result = {0, 0, 0};
    (void)chords;
    if (n_chords <= 0) return result;

    /* Build adjacency for connected components (BFS).
       Chords are vertices, transitions are edges.
       H0 = number of connected components.
       H1 = edges - vertices + components (cyclomatic number / Euler characteristic). */

    /* visited array */
    int* visited = (int*)calloc(n_chords, sizeof(int));
    int* queue   = (int*)malloc(n_chords * sizeof(int));
    /* adjacency: for each vertex, list of neighbors */
    int** adj = (int**)calloc(n_chords, sizeof(int*));
    int* adj_count = (int*)calloc(n_chords, sizeof(int));
    int* adj_cap   = (int*)calloc(n_chords, sizeof(int));

    /* build adjacency from transitions */
    for (int i = 0; i < n_transitions; i++) {
        int from = transitions[i * 2];
        int to   = transitions[i * 2 + 1];
        if (from < 0 || from >= n_chords || to < 0 || to >= n_chords) continue;

        /* add edge both ways for undirected connectivity */
        for (int pass = 0; pass < 2; pass++) {
            int u = pass == 0 ? from : to;
            int v = pass == 0 ? to : from;
            if (adj_count[u] >= adj_cap[u]) {
                adj_cap[u] = adj_cap[u] ? adj_cap[u] * 2 : 4;
                adj[u] = (int*)realloc(adj[u], adj_cap[u] * sizeof(int));
            }
            /* check for duplicate */
            int dup = 0;
            for (int k = 0; k < adj_count[u]; k++) {
                if (adj[u][k] == v) { dup = 1; break; }
            }
            if (!dup) adj[u][adj_count[u]++] = v;
        }
    }

    /* BFS for connected components */
    int h0 = 0;
    for (int start = 0; start < n_chords; start++) {
        if (visited[start]) continue;
        h0++;
        int qfront = 0, qback = 0;
        queue[qback++] = start;
        visited[start] = 1;
        while (qfront < qback) {
            int u = queue[qfront++];
            for (int k = 0; k < adj_count[u]; k++) {
                int v = adj[u][k];
                if (!visited[v]) {
                    visited[v] = 1;
                    queue[qback++] = v;
                }
            }
        }
    }

    /* Count unique undirected edges */
    int unique_edges = 0;
    for (int i = 0; i < n_chords; i++) unique_edges += adj_count[i];
    unique_edges /= 2; /* each edge counted twice */

    /* H1 = edges - vertices + components (cyclomatic number) */
    int h1 = unique_edges - n_chords + h0;
    if (h1 < 0) h1 = 0;

    result.h0 = h0;
    result.h1 = h1;
    result.emergence_detected = h1 > 0 ? 1 : 0;

    /* cleanup */
    for (int i = 0; i < n_chords; i++) free(adj[i]);
    free(adj); free(adj_count); free(adj_cap);
    free(visited); free(queue);

    return result;
}

/* ── Penrose Music ────────────────────────────────────────────────── */

/* Internal: 5D cut-and-project with golden projection */

#define WM_PENROSE_DIM 5
#define WM_PENROSE_MAX_TILES 8192

typedef struct {
    double x, y;
    int source[WM_PENROSE_DIM];
    int tile_type; /* 0=thick, 1=thin */
} wm__tile;

static void wm__golden_projection(double proj[2][WM_PENROSE_DIM]) {
    for (int k = 0; k < WM_PENROSE_DIM; k++) {
        double angle = k * (2.0 * WM_PI / 5.0);
        proj[0][k] = cos(angle);
        proj[1][k] = sin(angle);
    }
}

static void wm__mat_vec_5(const double mat[][WM_PENROSE_DIM], const double vec[WM_PENROSE_DIM], double out[2]) {
    for (int r = 0; r < 2; r++) {
        out[r] = 0;
        for (int j = 0; j < WM_PENROSE_DIM; j++) out[r] += mat[r][j] * vec[j];
    }
}

static void wm__gram_schmidt_perp(const double proj[2][WM_PENROSE_DIM], double perp[3][WM_PENROSE_DIM]) {
    /* Gram-Schmidt to find 3 perpendicular basis vectors in 5D */
    double basis[5][WM_PENROSE_DIM];
    int n_basis = 0;

    /* Start with projection rows, normalized */
    for (int r = 0; r < 2; r++) {
        double norm = 0;
        for (int j = 0; j < WM_PENROSE_DIM; j++) norm += proj[r][j] * proj[r][j];
        norm = sqrt(norm);
        for (int j = 0; j < WM_PENROSE_DIM; j++) basis[n_basis][j] = proj[r][j] / (norm > 1e-12 ? norm : 1.0);
        n_basis++;
    }

    /* Extend with standard basis vectors */
    for (int i = 0; i < WM_PENROSE_DIM && n_basis < WM_PENROSE_DIM; i++) {
        double e[WM_PENROSE_DIM];
        for (int j = 0; j < WM_PENROSE_DIM; j++) e[j] = (j == i) ? 1.0 : 0.0;
        /* orthogonalize against existing basis */
        for (int b = 0; b < n_basis; b++) {
            double d = 0;
            for (int j = 0; j < WM_PENROSE_DIM; j++) d += e[j] * basis[b][j];
            for (int j = 0; j < WM_PENROSE_DIM; j++) e[j] -= d * basis[b][j];
        }
        double norm = 0;
        for (int j = 0; j < WM_PENROSE_DIM; j++) norm += e[j] * e[j];
        norm = sqrt(norm);
        if (norm > 1e-12) {
            for (int j = 0; j < WM_PENROSE_DIM; j++) basis[n_basis][j] = e[j] / norm;
            n_basis++;
        }
    }

    /* Perpendicular rows are basis[2], basis[3], basis[4] */
    for (int i = 0; i < 3; i++) {
        int idx = 2 + i;
        if (idx < n_basis) {
            for (int j = 0; j < WM_PENROSE_DIM; j++) perp[i][j] = basis[idx][j];
        } else {
            for (int j = 0; j < WM_PENROSE_DIM; j++) perp[i][j] = 0.0;
        }
    }
}

static int wm__compile_penrose(int range, double groove_width, wm__tile* tiles, int max_tiles) {
    double proj[2][WM_PENROSE_DIM];
    double perp[3][WM_PENROSE_DIM];
    wm__golden_projection(proj);
    wm__gram_schmidt_perp(proj, perp);

    int count = 0;
    int coords[WM_PENROSE_DIM];

    /* iterate over 5D lattice cube [-range, range]^5 */
    for (coords[0] = -range; coords[0] <= range && count < max_tiles; coords[0]++)
    for (coords[1] = -range; coords[1] <= range && count < max_tiles; coords[1]++)
    for (coords[2] = -range; coords[2] <= range && count < max_tiles; coords[2]++)
    for (coords[3] = -range; coords[3] <= range && count < max_tiles; coords[3]++)
    for (coords[4] = -range; coords[4] <= range && count < max_tiles; coords[4]++) {
        double src[WM_PENROSE_DIM];
        for (int j = 0; j < WM_PENROSE_DIM; j++) src[j] = (double)coords[j];

        /* check perpendicular window */
        double pv[3] = {0, 0, 0};
        for (int r = 0; r < 3; r++)
            for (int j = 0; j < WM_PENROSE_DIM; j++)
                pv[r] += perp[r][j] * src[j];

        int accepted = 1;
        for (int r = 0; r < 3; r++) {
            if (fabs(pv[r]) >= groove_width) { accepted = 0; break; }
        }
        if (!accepted) continue;

        /* project to 2D */
        double target[2];
        wm__mat_vec_5(proj, src, target);

        /* classify tile */
        double s = 0;
        for (int j = 0; j < WM_PENROSE_DIM; j++) s += fabs((double)coords[j]);
        s *= WM_INV_PHI;
        double frac = s - floor(s);
        int tile_type = (frac < WM_INV_PHI) ? 0 : 1;

        tiles[count].x = target[0];
        tiles[count].y = target[1];
        for (int j = 0; j < WM_PENROSE_DIM; j++) tiles[count].source[j] = coords[j];
        tiles[count].tile_type = tile_type;
        count++;
    }
    return count;
}

void wm_penrose_rhythm(int range, double groove_width, int* hits, int* n_hits) {
    wm__tile* tiles = (wm__tile*)malloc(WM_PENROSE_MAX_TILES * sizeof(wm__tile));
    int count = wm__compile_penrose(range, groove_width, tiles, WM_PENROSE_MAX_TILES);
    if (count == 0) { *n_hits = 0; free(tiles); return; }

    /* normalize x to [0,1], quantize to hit positions */
    double xmin = tiles[0].x, xmax = tiles[0].x;
    for (int i = 1; i < count; i++) {
        if (tiles[i].x < xmin) xmin = tiles[i].x;
        if (tiles[i].x > xmax) xmax = tiles[i].x;
    }
    double span = xmax - xmin;
    if (span < 1e-12) span = 1.0;

    *n_hits = count < WM_MAX_HITS ? count : WM_MAX_HITS;
    for (int i = 0; i < *n_hits; i++) {
        hits[i] = (int)((tiles[i].x - xmin) / span * 16.0);
    }

    /* sort */
    for (int i = 0; i < *n_hits - 1; i++)
        for (int j = i + 1; j < *n_hits; j++)
            if (hits[i] > hits[j]) { int t = hits[i]; hits[i] = hits[j]; hits[j] = t; }

    free(tiles);
}

void wm_penrose_melody(const int* scale, int scale_len, int range,
                       int* notes, int* n_notes) {
    wm__tile* tiles = (wm__tile*)malloc(WM_PENROSE_MAX_TILES * sizeof(wm__tile));
    int count = wm__compile_penrose(range, 0.5, tiles, WM_PENROSE_MAX_TILES);
    if (count == 0) { *n_notes = 0; free(tiles); return; }

    double xmin = tiles[0].x, xmax = tiles[0].x;
    double ymin = tiles[0].y, ymax = tiles[0].y;
    for (int i = 1; i < count; i++) {
        if (tiles[i].x < xmin) xmin = tiles[i].x;
        if (tiles[i].x > xmax) xmax = tiles[i].x;
        if (tiles[i].y < ymin) ymin = tiles[i].y;
        if (tiles[i].y > ymax) ymax = tiles[i].y;
    }
    double yspan = ymax - ymin;
    if (yspan < 1e-12) yspan = 1.0;

    int max_notes = count < 32 ? count : 32;
    *n_notes = max_notes;
    for (int i = 0; i < max_notes; i++) {
        double y_norm = (tiles[i].y - ymin) / yspan;
        int sidx = (int)(y_norm * (scale_len - 1));
        if (sidx < 0) sidx = 0;
        if (sidx >= scale_len) sidx = scale_len - 1;
        int oct_off = (int)(y_norm * 2) - 1;
        int midi = 12 * (5 + oct_off) + scale[sidx];
        if (midi < 0) midi = 0;
        if (midi > 127) midi = 127;
        notes[i] = midi;
    }
    free(tiles);
}

/* ── Utility ──────────────────────────────────────────────────────── */

double wm_ratio_to_cents(double ratio) {
    return 1200.0 * log2(ratio);
}

int wm_approx_eq(double a, double b, double epsilon) {
    return fabs(a - b) < epsilon;
}

#endif /* WORLD_MUSIC_IMPLEMENTATION */
