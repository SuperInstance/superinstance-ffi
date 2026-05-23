/*
 * test_spline_synth.c — 20+ tests for the spline wavetable synthesizer
 * Compile: cc -O2 -lm -DSPLINE_SYNTH_IMPLEMENTATION test_spline_synth.c -o test_spline_synth
 */

#define SPLINE_SYNTH_IMPLEMENTATION
#include "spline_synth.h"

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

static int g_pass = 0, g_fail = 0;

#define ASSERT(cond, msg) do { \
    if (!(cond)) { \
        printf("  FAIL: %s — %s\n", __func__, msg); \
        g_fail++; return; \
    } \
} while(0)

#define ASSERT_F(cond, fmt, ...) do { \
    if (!(cond)) { \
        printf("  FAIL: %s — " fmt "\n", __func__, ##__VA_ARGS__); \
        g_fail++; return; \
    } \
} while(0)

#define RUN(fn) do { \
    printf("  %-50s", #fn); \
    fn(); \
    printf("OK\n"); \
    g_pass++; \
} while(0)

/* ---- Tests ---- */

static void test_init_free(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 1024, 16);
    ASSERT(swt.table_size == 1024, "table_size");
    ASSERT(swt.n_points == 16, "n_points");
    ASSERT(swt.points != NULL, "points allocated");
    ASSERT(swt.table != NULL, "table allocated");
    ASSERT(swt.interp_matrix != NULL, "interp_matrix allocated");
    spline_wavetable_free(&swt);
    ASSERT(swt.points == NULL, "points freed");
    ASSERT(swt.table == NULL, "table freed");
}

static void test_lattice_first_point_origin(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 512, 7);
    ASSERT(fabs(swt.points[0].x) < 1e-9, "x ~= 0");
    ASSERT(fabs(swt.points[0].y) < 1e-9, "y ~= 0");
    spline_wavetable_free(&swt);
}

static void test_lattice_normalized(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 256, 32);
    double max_dist = 0.0;
    for (int i = 0; i < swt.n_points; i++) {
        double d = sqrt(swt.points[i].x * swt.points[i].x + swt.points[i].y * swt.points[i].y);
        if (d > max_dist) max_dist = d;
    }
    ASSERT_F(fabs(max_dist - 1.0) < 0.01, "max_dist = %f", max_dist);
    spline_wavetable_free(&swt);
}

static void test_interp_matrix_rows_sum_to_one(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 256, 16);
    for (int i = 0; i < swt.table_size; i++) {
        double sum = 0.0;
        for (int j = 0; j < swt.n_points; j++) {
            sum += swt.interp_matrix[i * swt.n_points + j];
        }
        ASSERT_F(fabs(sum - 1.0) < 1e-9, "row %d sum = %f", i, sum);
    }
    spline_wavetable_free(&swt);
}

static void test_interp_matrix_all_positive(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 512, 16);
    for (int i = 0; i < swt.table_size * swt.n_points; i++) {
        ASSERT(swt.interp_matrix[i] >= 0.0, "negative weight");
    }
    spline_wavetable_free(&swt);
}

static void test_reconstruct_zero_values(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 512, 16);
    double zeros[16] = {0};
    spline_wavetable_set_values(&swt, zeros, 16);
    spline_wavetable_reconstruct(&swt);
    for (int i = 0; i < swt.table_size; i++) {
        ASSERT_F(fabs(swt.table[i]) < 1e-12, "table[%d] = %f", i, swt.table[i]);
    }
    spline_wavetable_free(&swt);
}

static void test_reconstruct_uniform_values(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 512, 16);
    double ones[16];
    for (int i = 0; i < 16; i++) ones[i] = 1.0;
    spline_wavetable_set_values(&swt, ones, 16);
    spline_wavetable_reconstruct(&swt);
    for (int i = 0; i < swt.table_size; i++) {
        ASSERT_F(fabs(swt.table[i] - 1.0) < 1e-9, "table[%d] = %f", i, swt.table[i]);
    }
    spline_wavetable_free(&swt);
}

static void test_sample_phase_zero(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 1024, 16);
    spline_preset_sine(&swt);
    float s = spline_wavetable_sample(&swt, 0.0f);
    /* Sine at phase 0 should be near 0 */
    ASSERT_F(fabs(s) < 0.1, "sample(0) = %f", s);
    spline_wavetable_free(&swt);
}

static void test_sample_phase_range(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 2048, 32);
    spline_preset_sine(&swt);
    /* Sine should be bounded */
    for (int i = 0; i < 100; i++) {
        float phase = (float)i / 100.0f;
        float s = spline_wavetable_sample(&swt, phase);
        ASSERT_F(s >= -2.0f && s <= 2.0f, "phase=%f sample=%f out of range", phase, s);
    }
    spline_wavetable_free(&swt);
}

static void test_preset_sine(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 2048, 32);
    spline_preset_sine(&swt);
    /* Generate target sine */
    double* target = (double*)malloc(2048 * sizeof(double));
    for (int i = 0; i < 2048; i++) target[i] = sin(2.0 * 3.14159265358979323846 * i / 2048.0);
    double rmse = spline_reconstruction_error(&swt, target, 2048);
    ASSERT_F(rmse < 0.05, "sine RMSE = %f", rmse);
    free(target);
    spline_wavetable_free(&swt);
}

static void test_preset_saw(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 2048, 64);
    spline_preset_saw(&swt);
    /* Check table is non-zero and roughly monotonic in sections */
    int has_pos = 0, has_neg = 0;
    for (int i = 0; i < swt.table_size; i++) {
        if (swt.table[i] > 0.5) has_pos = 1;
        if (swt.table[i] < -0.5) has_neg = 1;
    }
    ASSERT(has_pos && has_neg, "sawtooth should span positive and negative");
    spline_wavetable_free(&swt);
}

static void test_preset_square(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 2048, 64);
    spline_preset_square(&swt);
    /* Square should have values near +1 and -1 */
    int near_pos = 0, near_neg = 0;
    for (int i = 0; i < swt.table_size; i++) {
        if (swt.table[i] > 0.5) near_pos++;
        if (swt.table[i] < -0.5) near_neg++;
    }
    ASSERT(near_pos > swt.table_size / 4, "not enough positive samples");
    ASSERT(near_neg > swt.table_size / 4, "not enough negative samples");
    spline_wavetable_free(&swt);
}

static void test_preset_triangle(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 2048, 32);
    spline_preset_triangle(&swt);
    double* target = (double*)malloc(2048 * sizeof(double));
    for (int i = 0; i < 2048; i++) {
        double t = (double)i / 2048.0;
        target[i] = 4.0 * fabs(t - 0.5) - 1.0;
    }
    double rmse = spline_reconstruction_error(&swt, target, 2048);
    ASSERT_F(rmse < 0.05, "triangle RMSE = %f", rmse);
    free(target);
    spline_wavetable_free(&swt);
}

static void test_morph_midpoint(void) {
    SplineWavetable swt_a, swt_b, swt_out;
    spline_wavetable_init(&swt_a, 512, 16);
    spline_wavetable_init(&swt_b, 512, 16);
    spline_wavetable_init(&swt_out, 512, 16);
    spline_preset_sine(&swt_a);
    spline_preset_saw(&swt_b);
    spline_morph(&swt_a, &swt_b, 0.5f, &swt_out);
    /* Morphed table should be non-zero and bounded */
    int non_zero = 0;
    for (int i = 0; i < 512; i++) {
        if (fabs(swt_out.table[i]) > 1e-6) non_zero++;
        ASSERT_F(swt_out.table[i] >= -2.0 && swt_out.table[i] <= 2.0,
                 "table[%d] = %f out of range", i, swt_out.table[i]);
    }
    ASSERT(non_zero > 100, "morphed table should be non-trivial");
    spline_wavetable_free(&swt_a);
    spline_wavetable_free(&swt_b);
    spline_wavetable_free(&swt_out);
}

static void test_morph_t_zero_is_a(void) {
    SplineWavetable swt_a, swt_b, swt_out;
    spline_wavetable_init(&swt_a, 512, 16);
    spline_wavetable_init(&swt_b, 512, 16);
    spline_wavetable_init(&swt_out, 512, 16);
    spline_preset_sine(&swt_a);
    spline_preset_saw(&swt_b);
    spline_morph(&swt_a, &swt_b, 0.0f, &swt_out);
    /* With t=0, values should match a exactly */
    for (int i = 0; i < 16; i++) {
        ASSERT_F(fabs(swt_out.points[i].value - swt_a.points[i].value) < 1e-12,
                 "cp[%d] mismatch: %f vs %f", i, swt_out.points[i].value, swt_a.points[i].value);
    }
    spline_wavetable_free(&swt_a);
    spline_wavetable_free(&swt_b);
    spline_wavetable_free(&swt_out);
}

static void test_morph_t_one_is_b(void) {
    SplineWavetable swt_a, swt_b, swt_out;
    spline_wavetable_init(&swt_a, 512, 16);
    spline_wavetable_init(&swt_b, 512, 16);
    spline_wavetable_init(&swt_out, 512, 16);
    spline_preset_sine(&swt_a);
    spline_preset_saw(&swt_b);
    spline_morph(&swt_a, &swt_b, 1.0f, &swt_out);
    for (int i = 0; i < 16; i++) {
        ASSERT_F(fabs(swt_out.points[i].value - swt_b.points[i].value) < 1e-12,
                 "cp[%d] mismatch: %f vs %f", i, swt_out.points[i].value, swt_b.points[i].value);
    }
    spline_wavetable_free(&swt_a);
    spline_wavetable_free(&swt_b);
    spline_wavetable_free(&swt_out);
}

static void test_render_length(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 2048, 16);
    spline_preset_sine(&swt);
    int n_samples = 0;
    float* audio = spline_wavetable_render(&swt, 440.0f, 0.5f, 44100, &n_samples);
    ASSERT_F(n_samples == 22050, "n_samples = %d", n_samples);
    free(audio);
    spline_wavetable_free(&swt);
}

static void test_render_bounded(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 2048, 16);
    spline_preset_sine(&swt);
    int n_samples = 0;
    float* audio = spline_wavetable_render(&swt, 440.0f, 0.1f, 44100, &n_samples);
    for (int i = 0; i < n_samples; i++) {
        ASSERT_F(audio[i] >= -2.0f && audio[i] <= 2.0f,
                 "audio[%d] = %f out of bounds", i, audio[i]);
    }
    free(audio);
    spline_wavetable_free(&swt);
}

static void test_render_nonzero(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 2048, 16);
    spline_preset_sine(&swt);
    int n_samples = 0;
    float* audio = spline_wavetable_render(&swt, 440.0f, 0.1f, 44100, &n_samples);
    int nonzero = 0;
    for (int i = 0; i < n_samples; i++) {
        if (fabs(audio[i]) > 1e-6f) nonzero++;
    }
    ASSERT_F(nonzero > n_samples / 2, "only %d/%d non-zero", nonzero, n_samples);
    free(audio);
    spline_wavetable_free(&swt);
}

static void test_render_saw_different_from_sine(void) {
    SplineWavetable swt_sine, swt_saw;
    spline_wavetable_init(&swt_sine, 2048, 32);
    spline_wavetable_init(&swt_saw, 2048, 32);
    spline_preset_sine(&swt_sine);
    spline_preset_saw(&swt_saw);
    int n1 = 0, n2 = 0;
    float* a1 = spline_wavetable_render(&swt_sine, 440.0f, 0.01f, 44100, &n1);
    float* a2 = spline_wavetable_render(&swt_saw, 440.0f, 0.01f, 44100, &n2);
    double diff = 0.0;
    for (int i = 0; i < n1 && i < n2; i++) {
        double d = (double)a1[i] - (double)a2[i];
        diff += d * d;
    }
    diff = sqrt(diff / (double)(n1 < n2 ? n1 : n2));
    ASSERT_F(diff > 0.01, "sine and saw too similar, RMSE = %f", diff);
    free(a1); free(a2);
    spline_wavetable_free(&swt_sine);
    spline_wavetable_free(&swt_saw);
}

static void test_compression_ratio(void) {
    /* 2048 table / 16 control points = 128× */
    SplineWavetable swt;
    spline_wavetable_init(&swt, 2048, 16);
    ASSERT(swt.table_size == 2048, "table_size");
    ASSERT(swt.n_points == 16, "n_points");
    /* ratio = table_size / n_points = 128 */
    double ratio = (double)swt.table_size / (double)swt.n_points;
    ASSERT_F(fabs(ratio - 128.0) < 0.01, "ratio = %f", ratio);
    spline_wavetable_free(&swt);
}

static void test_reconstruction_error(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 1024, 32);
    spline_preset_sine(&swt);
    /* Error vs itself should be 0 */
    double err = spline_reconstruction_error(&swt, swt.table, swt.table_size);
    ASSERT_F(fabs(err) < 1e-12, "self-error = %f", err);
    spline_wavetable_free(&swt);
}

static void test_multiple_presets_differ(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 1024, 32);
    spline_preset_sine(&swt);
    double sine_peak = 0.0;
    for (int i = 0; i < swt.table_size; i++) sine_peak += fabs(swt.table[i]);
    spline_preset_saw(&swt);
    double saw_peak = 0.0;
    for (int i = 0; i < swt.table_size; i++) saw_peak += fabs(swt.table[i]);
    /* They should produce different total energy */
    ASSERT_F(fabs(sine_peak - saw_peak) > 1.0, "sine=%f saw=%f too similar", sine_peak, saw_peak);
    spline_wavetable_free(&swt);
}

static void test_large_table(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 4096, 64);
    spline_preset_sine(&swt);
    ASSERT(swt.table_size == 4096, "table_size");
    int nonzero = 0;
    for (int i = 0; i < 4096; i++) {
        if (fabs(swt.table[i]) > 1e-6) nonzero++;
    }
    ASSERT(nonzero > 2048, "large table should have data");
    spline_wavetable_free(&swt);
}

static void test_few_control_points(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 256, 4);
    spline_preset_sine(&swt);
    /* With only 4 control points, reconstruction should still produce something */
    int nonzero = 0;
    for (int i = 0; i < 256; i++) {
        if (fabs(swt.table[i]) > 1e-6) nonzero++;
    }
    ASSERT(nonzero > 50, "should have some signal");
    spline_wavetable_free(&swt);
}

static void test_set_values_reconstruct(void) {
    SplineWavetable swt;
    spline_wavetable_init(&swt, 256, 8);
    double vals[8] = {0, 1, 0, -1, 0, 1, 0, -1};
    spline_wavetable_set_values(&swt, vals, 8);
    spline_wavetable_reconstruct(&swt);
    /* Should not be all zeros */
    int nonzero = 0;
    for (int i = 0; i < 256; i++) {
        if (fabs(swt.table[i]) > 1e-6) nonzero++;
    }
    ASSERT(nonzero > 50, "should have signal from non-zero values");
    spline_wavetable_free(&swt);
}

/* ---- Main ---- */

int main(void) {
    printf("\n============================================================\n");
    printf("Spline Wavetable Synthesizer — C Tests\n");
    printf("============================================================\n\n");

    RUN(test_init_free);
    RUN(test_lattice_first_point_origin);
    RUN(test_lattice_normalized);
    RUN(test_interp_matrix_rows_sum_to_one);
    RUN(test_interp_matrix_all_positive);
    RUN(test_reconstruct_zero_values);
    RUN(test_reconstruct_uniform_values);
    RUN(test_sample_phase_zero);
    RUN(test_sample_phase_range);
    RUN(test_preset_sine);
    RUN(test_preset_saw);
    RUN(test_preset_square);
    RUN(test_preset_triangle);
    RUN(test_morph_midpoint);
    RUN(test_morph_t_zero_is_a);
    RUN(test_morph_t_one_is_b);
    RUN(test_render_length);
    RUN(test_render_bounded);
    RUN(test_render_nonzero);
    RUN(test_render_saw_different_from_sine);
    RUN(test_compression_ratio);
    RUN(test_reconstruction_error);
    RUN(test_multiple_presets_differ);
    RUN(test_large_table);
    RUN(test_few_control_points);
    RUN(test_set_values_reconstruct);

    printf("\n============================================================\n");
    printf("  Passed: %d  Failed: %d  Total: %d\n",
           g_pass, g_fail, g_pass + g_fail);
    printf("============================================================\n\n");

    return g_fail > 0 ? 1 : 0;
}
