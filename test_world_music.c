/*
 * test_world_music.c — 40+ test assertions for world_music.h
 */

#define WORLD_MUSIC_IMPLEMENTATION
#include "world_music.h"

#include <stdio.h>

static int tests_passed = 0;
static int tests_total = 0;

#define TEST(name) static void test_##name(void)
#define RUN(name) do { printf("  %-50s", #name); test_##name(); tests_passed++; tests_total++; printf("PASS\n"); } while(0)
#define ASSERT(cond) do { if (!(cond)) { printf("FAIL\n  Assertion failed: %s\n  File: %s:%d\n", #cond, __FILE__, __LINE__); exit(1); } tests_total++; } while(0)

/* ── Scale tests ──────────────────────────────────────────────────── */

TEST(scale_lookup) {
    const WorldScale* s = wm_scale("bhairavi");
    ASSERT(s != NULL);
    ASSERT(s->note_count == 7);
    ASSERT(s->notes[0] == 0);
    ASSERT(s->notes[1] == 1);
    ASSERT(s->notes[6] == 10);
    ASSERT(s->vadi == 1);
    ASSERT(s->samvadi == 5);
}

TEST(scale_case_insensitive) {
    ASSERT(wm_scale("Bhairavi") != NULL);
    ASSERT(wm_scale("BHAIravI") != NULL);
}

TEST(scale_not_found) {
    ASSERT(wm_scale("nonexistent_scale") == NULL);
}

TEST(scale_count) {
    int count;
    wm_all_scales(&count);
    ASSERT(count == 36);
}

TEST(scales_by_culture_indian) {
    int count;
    const WorldScale* s = wm_scales_by_culture("indian", &count);
    ASSERT(s != NULL);
    ASSERT(count == 10);
}

TEST(scales_by_culture_arabic) {
    int count;
    const WorldScale* s = wm_scales_by_culture("arabic", &count);
    ASSERT(s != NULL);
    ASSERT(count == 10);
}

TEST(scales_by_culture_japanese) {
    int count;
    const WorldScale* s = wm_scales_by_culture("japanese", &count);
    ASSERT(s != NULL);
    ASSERT(count == 4);
}

TEST(scale_to_midi_yaman) {
    int notes[64];
    int n = wm_scale_to_midi("yaman", 60, 2, notes, 64);
    ASSERT(n > 0);
    /* Yaman: [0,2,4,6,7,9,11] from root 60 → [60,62,64,66,67,69,71, ...] */
    ASSERT(notes[0] == 60);
    ASSERT(notes[1] == 62);
    ASSERT(notes[2] == 64);
}

TEST(pentatonic_major_notes) {
    const WorldScale* s = wm_scale("pentatonic_major");
    ASSERT(s != NULL);
    ASSERT(s->note_count == 5);
    ASSERT(s->notes[0] == 0);
    ASSERT(s->notes[4] == 9);
}

/* ── Tuning tests ─────────────────────────────────────────────────── */

TEST(equal_temperament) {
    const TuningSystem* et = wm_tuning_equal_temperament();
    ASSERT(et != NULL);
    ASSERT(et->divisions == 12);
    ASSERT(wm_approx_eq(wm_tuning_cents(et, 0), 0.0, 0.01));
    ASSERT(wm_approx_eq(wm_tuning_cents(et, 1), 100.0, 0.01));
    ASSERT(wm_approx_eq(wm_tuning_cents(et, 7), 700.0, 0.01));
    ASSERT(wm_approx_eq(wm_tuning_cents(et, 12), 1200.0, 0.01));
}

TEST(just_intonation) {
    const TuningSystem* ji = wm_tuning_just_intonation();
    ASSERT(ji != NULL);
    ASSERT(ji->divisions == 12);
    ASSERT(wm_approx_eq(wm_tuning_cents(ji, 0), 0.0, 0.01));
    /* 5/4 = 386.31 cents */
    ASSERT(wm_approx_eq(wm_tuning_cents(ji, 4), 386.31, 0.1));
    /* 3/2 = 701.96 cents */
    ASSERT(wm_approx_eq(wm_tuning_cents(ji, 7), 701.96, 0.1));
}

TEST(shruti_22) {
    const TuningSystem* sh = wm_tuning_shruti_22();
    ASSERT(sh != NULL);
    ASSERT(sh->divisions == 22);
    ASSERT(wm_approx_eq(wm_tuning_cents(sh, 0), 0.0, 0.01));
    /* 3/2 = Pa = index 13 */
    ASSERT(wm_approx_eq(wm_tuning_cents(sh, 13), 701.96, 0.1));
}

TEST(quarter_tone_24) {
    const TuningSystem* qt = wm_tuning_quarter_tone_24();
    ASSERT(qt != NULL);
    ASSERT(qt->divisions == 24);
    ASSERT(wm_approx_eq(wm_tuning_cents(qt, 1), 50.0, 0.01));
    ASSERT(wm_approx_eq(wm_tuning_cents(qt, 12), 600.0, 0.01));
}

TEST(pentatonic_5_tuning) {
    const TuningSystem* p = wm_tuning_pentatonic_5();
    ASSERT(p != NULL);
    ASSERT(p->divisions == 5);
    ASSERT(wm_approx_eq(wm_tuning_cents(p, 1), 240.0, 0.01));
}

TEST(pythagorean_tuning) {
    const TuningSystem* py = wm_tuning_pythagorean();
    ASSERT(py != NULL);
    ASSERT(py->divisions == 12);
    /* Pythagorean fifth = ~701.955 cents */
    double fifth = wm_tuning_cents(py, 7);
    ASSERT(fifth > 700.0 && fifth < 705.0);
}

TEST(meantone_tuning) {
    const TuningSystem* mt = wm_tuning_meantone();
    ASSERT(mt != NULL);
    ASSERT(mt->divisions == 12);
    /* Meantone fifth ~696.578 */
    double fifth = wm_tuning_cents(mt, 7);
    ASSERT(fifth > 695.0 && fifth < 700.0);
}

TEST(snap_to_tuning) {
    const TuningSystem* et = wm_tuning_equal_temperament();
    double snapped = wm_snap_to_tuning(99.5, et, 0);
    ASSERT(wm_approx_eq(snapped, 100.0, 0.01));
    /* With small epsilon, far notes don't snap */
    double no_snap = wm_snap_to_tuning(95.0, et, 2.0);
    ASSERT(wm_approx_eq(no_snap, 95.0, 0.01));
}

TEST(tuning_all_cents) {
    const TuningSystem* et = wm_tuning_equal_temperament();
    double cents[12];
    int n = wm_tuning_all_cents(et, cents, 12);
    ASSERT(n == 12);
    ASSERT(wm_approx_eq(cents[0], 0.0, 0.01));
    ASSERT(wm_approx_eq(cents[11], 1100.0, 0.01));
}

/* ── Ornament tests ───────────────────────────────────────────────── */

TEST(meend_basic) {
    double out[21];
    wm_ornament_meend(0.0, 12.0, 20, 0, out); /* exponential */
    ASSERT(wm_approx_eq(out[0], 0.0, 0.001));
    ASSERT(wm_approx_eq(out[20], 12.0, 0.001));
    /* Exponential: slow start, so middle should be < 6.0 */
    ASSERT(out[10] < 6.0);
}

TEST(meend_linear) {
    double out[11];
    wm_ornament_meend(0.0, 10.0, 10, 2, out); /* linear */
    ASSERT(wm_approx_eq(out[5], 5.0, 0.001));
    ASSERT(wm_approx_eq(out[10], 10.0, 0.001));
}

TEST(meend_logarithmic) {
    double out[11];
    wm_ornament_meend(0.0, 10.0, 10, 1, out);
    ASSERT(wm_approx_eq(out[0], 0.0, 0.001));
    ASSERT(wm_approx_eq(out[10], 10.0, 0.001));
    /* Logarithmic: fast start, so middle should be > 5.0 */
    ASSERT(out[5] > 5.0);
}

TEST(gamak_basic) {
    double out[200];
    int n = wm_ornament_gamak(5.0, 0.5, 6.0, 3, out);
    ASSERT(n > 0);
    /* Center value should appear (approximately) */
    ASSERT(out[0] > 4.0 && out[0] < 6.0);
}

TEST(quarter_bend_up) {
    double out[30];
    int n = wm_ornament_quarter_bend(5.0, 0, 50.0, 10, out);
    ASSERT(n > 0);
    /* Should start at note and end at note */
    ASSERT(wm_approx_eq(out[0], 5.0, 0.001));
    ASSERT(wm_approx_eq(out[n-1], 5.0, 0.001));
}

TEST(shakes_basic) {
    double out[200];
    int n = wm_ornament_shakes(5.0, 8.0, 0.3, out, 200);
    ASSERT(n > 0);
    /* Should oscillate around center */
    double min_val = out[0], max_val = out[0];
    for (int i = 1; i < n; i++) {
        if (out[i] < min_val) min_val = out[i];
        if (out[i] > max_val) max_val = out[i];
    }
    ASSERT(min_val < 5.0);
    ASSERT(max_val > 5.0);
}

/* ── Rhythm tests ─────────────────────────────────────────────────── */

TEST(rhythm_son_clave) {
    const RhythmPattern* r = wm_rhythm("son_2_3");
    ASSERT(r != NULL);
    ASSERT(r->hit_count == 5);
    ASSERT(r->hits[0] == 0);
    ASSERT(r->hits[4] == 11);
}

TEST(rhythm_bossa_nova) {
    const RhythmPattern* r = wm_rhythm("bossa_nova");
    ASSERT(r != NULL);
    ASSERT(r->hit_count == 6);
}

TEST(rhythm_agbadza) {
    const RhythmPattern* r = wm_rhythm("agbadza");
    ASSERT(r != NULL);
    ASSERT(r->hit_count == 6);
    ASSERT(r->hits[0] == 0);
}

TEST(rhythm_teental) {
    const RhythmPattern* r = wm_rhythm("teental");
    ASSERT(r != NULL);
    ASSERT(r->subdivisions == 16);
    ASSERT(r->hit_count == 4);
}

TEST(rhythm_count) {
    int count;
    wm_all_rhythms(&count);
    ASSERT(count == 26);
}

TEST(rhythm_not_found) {
    ASSERT(wm_rhythm("nonexistent") == NULL);
}

/* ── Cohomology tests ─────────────────────────────────────────────── */

TEST(cohomology_single_chord) {
    int chords[] = {0};
    CohomologyResult r = wm_musical_cohomology(chords, 1, NULL, 0);
    ASSERT(r.h0 == 1);
    ASSERT(r.h1 == 0);
    ASSERT(r.emergence_detected == 0);
}

TEST(cohomology_cycle) {
    /* 3 chords in a cycle: 0→1, 1→2, 2→0 → H1=1 */
    int chords[] = {0, 4, 7};
    int trans[] = {0,1, 1,2, 2,0};
    CohomologyResult r = wm_musical_cohomology(chords, 3, trans, 3);
    ASSERT(r.h0 == 1);
    ASSERT(r.h1 == 1);
    ASSERT(r.emergence_detected == 1);
}

TEST(cohomology_disconnected) {
    /* 4 chords, 2 pairs → H0=2 */
    int chords[] = {0, 1, 2, 3};
    int trans[] = {0,1, 2,3};
    CohomologyResult r = wm_musical_cohomology(chords, 4, trans, 2);
    ASSERT(r.h0 == 2);
}

TEST(cohomology_no_transitions) {
    int chords[] = {0, 4, 7};
    CohomologyResult r = wm_musical_cohomology(chords, 3, NULL, 0);
    ASSERT(r.h0 == 3);
    ASSERT(r.h1 == 0);
}

/* ── Penrose tests ────────────────────────────────────────────────── */

TEST(penrose_rhythm_basic) {
    int hits[32];
    int n;
    wm_penrose_rhythm(3, 0.5, hits, &n);
    ASSERT(n > 0);
    for (int i = 0; i < n; i++) {
        ASSERT(hits[i] >= 0 && hits[i] <= 16);
    }
}

TEST(penrose_rhythm_sorted) {
    int hits[32];
    int n;
    wm_penrose_rhythm(4, 0.6, hits, &n);
    for (int i = 1; i < n; i++) {
        ASSERT(hits[i] >= hits[i-1]);
    }
}

TEST(penrose_melody_basic) {
    int scale[] = {0, 2, 4, 7, 9};
    int notes[32];
    int n;
    wm_penrose_melody(scale, 5, 3, notes, &n);
    ASSERT(n > 0);
    for (int i = 0; i < n; i++) {
        ASSERT(notes[i] >= 0 && notes[i] <= 127);
    }
}

TEST(penrose_melody_larger_range) {
    int scale[] = {0, 2, 4, 7, 9};
    int notes1[32], notes2[32];
    int n1, n2;
    wm_penrose_melody(scale, 5, 2, notes1, &n1);
    wm_penrose_melody(scale, 5, 5, notes2, &n2);
    ASSERT(n2 >= n1);
}

/* ── Utility tests ────────────────────────────────────────────────── */

TEST(ratio_to_cents) {
    ASSERT(wm_approx_eq(wm_ratio_to_cents(2.0), 1200.0, 0.01));
    ASSERT(wm_approx_eq(wm_ratio_to_cents(1.0), 0.0, 0.01));
}

TEST(approx_eq) {
    ASSERT(wm_approx_eq(1.0, 1.0001, 0.01));
    ASSERT(!wm_approx_eq(1.0, 1.1, 0.01));
}

/* ── Main ─────────────────────────────────────────────────────────── */

int main(void) {
    printf("═══ world_music.h test suite ═══\n\n");

    RUN(scale_lookup);
    RUN(scale_case_insensitive);
    RUN(scale_not_found);
    RUN(scale_count);
    RUN(scales_by_culture_indian);
    RUN(scales_by_culture_arabic);
    RUN(scales_by_culture_japanese);
    RUN(scale_to_midi_yaman);
    RUN(pentatonic_major_notes);

    RUN(equal_temperament);
    RUN(just_intonation);
    RUN(shruti_22);
    RUN(quarter_tone_24);
    RUN(pentatonic_5_tuning);
    RUN(pythagorean_tuning);
    RUN(meantone_tuning);
    RUN(snap_to_tuning);
    RUN(tuning_all_cents);

    RUN(meend_basic);
    RUN(meend_linear);
    RUN(meend_logarithmic);
    RUN(gamak_basic);
    RUN(quarter_bend_up);
    RUN(shakes_basic);

    RUN(rhythm_son_clave);
    RUN(rhythm_bossa_nova);
    RUN(rhythm_agbadza);
    RUN(rhythm_teental);
    RUN(rhythm_count);
    RUN(rhythm_not_found);

    RUN(cohomology_single_chord);
    RUN(cohomology_cycle);
    RUN(cohomology_disconnected);
    RUN(cohomology_no_transitions);

    RUN(penrose_rhythm_basic);
    RUN(penrose_rhythm_sorted);
    RUN(penrose_melody_basic);
    RUN(penrose_melody_larger_range);

    RUN(ratio_to_cents);
    RUN(approx_eq);

    printf("\n%d/%d tests passed ✓\n", tests_passed, tests_total);
    return 0;
}
