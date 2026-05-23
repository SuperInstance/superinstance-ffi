/*
 * spline_synth.h — Single-header Spline Wavetable Synthesizer
 *
 * Eisenstein lattice control points for audio waveform synthesis.
 * Reconstruct wavetables from a handful of control points via IDW² interpolation.
 *
 * Usage:
 *   #define SPLINE_SYNTH_IMPLEMENTATION
 *   #include "spline_synth.h"
 *
 * Dependencies: -lm only
 */

#ifndef SPLINE_SYNTH_H
#define SPLINE_SYNTH_H

#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------ */
/* Types                                                               */
/* ------------------------------------------------------------------ */

typedef struct {
    double x;
    double y;
    double value;
} ControlPoint;

typedef struct {
    ControlPoint* points;    /* lattice positions + values, length n_points */
    int n_points;            /* number of control points */
    int table_size;          /* output wavetable length (e.g. 2048) */
    double* table;           /* reconstructed waveform [table_size] */
    double* interp_matrix;   /* precomputed (table_size × n_points) IDW² matrix */
} SplineWavetable;

/* ------------------------------------------------------------------ */
/* API                                                                 */
/* ------------------------------------------------------------------ */

/* Lifecycle */
void spline_wavetable_init(SplineWavetable* swt, int table_size, int n_control_points);
void spline_wavetable_free(SplineWavetable* swt);

/* Set control point values (positions come from lattice) */
void spline_wavetable_set_values(SplineWavetable* swt, const double* values, int n);

/* Reconstruct full wavetable from control points via IDW² */
void spline_wavetable_reconstruct(SplineWavetable* swt);

/* Sample the wavetable at phase ∈ [0,1), with linear interpolation */
float spline_wavetable_sample(const SplineWavetable* swt, float phase);

/* Morph: linear interpolation of control points from a → b */
void spline_morph(const SplineWavetable* a, const SplineWavetable* b, float t, SplineWavetable* out);

/* Presets: generate standard waveforms by fitting control points */
void spline_preset_sine(SplineWavetable* swt);
void spline_preset_saw(SplineWavetable* swt);
void spline_preset_square(SplineWavetable* swt);
void spline_preset_triangle(SplineWavetable* swt);

/* Render audio: returns malloc'd float array of n_samples, caller frees */
float* spline_wavetable_render(const SplineWavetable* swt, float frequency,
                               float duration, int sample_rate, int* out_n_samples);

/* Reconstruction RMSE vs target waveform */
double spline_reconstruction_error(const SplineWavetable* swt, const double* target, int target_len);

#ifdef __cplusplus
}
#endif

/* ------------------------------------------------------------------ */
/* Implementation                                                      */
/* ------------------------------------------------------------------ */

#ifdef SPLINE_SYNTH_IMPLEMENTATION

#define SS_PI 3.14159265358979323846
#define SS_SQRT3_HALF 0.86602540378443864676

/* ---- Internal: Eisenstein lattice builder ---- */

typedef struct { double x; double y; double dist_sq; } _SSCandidate;

static int _ss_cand_cmp(const void* a, const void* b) {
    const _SSCandidate* ca = (const _SSCandidate*)a;
    const _SSCandidate* cb = (const _SSCandidate*)b;
    double da = round(ca->dist_sq * 1e9);
    double db = round(cb->dist_sq * 1e9);
    if (da < db) return -1;
    if (da > db) return  1;
    if (ca->x < cb->x) return -1;
    if (ca->x > cb->x) return  1;
    if (ca->y < cb->y) return -1;
    if (ca->y > cb->y) return  1;
    return 0;
}

static void _ss_build_lattice(ControlPoint* pts, int n) {
    int R = (int)ceil(sqrt((double)n / 3.0)) + 2;
    if (R < 3) R = 3;
    int max_cand = (2 * R + 1) * (2 * R + 1);
    _SSCandidate* cands = (_SSCandidate*)malloc((size_t)max_cand * sizeof(_SSCandidate));
    int cnt = 0;
    for (int a = -R; a <= R; a++) {
        for (int b = -R; b <= R; b++) {
            double x = (double)a - (double)b * 0.5;
            double y = (double)b * SS_SQRT3_HALF;
            double d = x * x + y * y;
            cands[cnt].x = x;
            cands[cnt].y = y;
            cands[cnt].dist_sq = d;
            cnt++;
        }
    }
    qsort(cands, (size_t)cnt, sizeof(_SSCandidate), _ss_cand_cmp);
    /* Find max distance for normalization */
    double max_dist = 0.0;
    for (int i = 0; i < n && i < cnt; i++) {
        double d = sqrt(cands[i].dist_sq);
        if (d > max_dist) max_dist = d;
    }
    if (max_dist < 1e-12) max_dist = 1.0;
    for (int i = 0; i < n && i < cnt; i++) {
        pts[i].x = cands[i].x / max_dist;
        pts[i].y = cands[i].y / max_dist;
        pts[i].value = 0.0;
    }
    free(cands);
}

/* ---- Internal: IDW² interpolation matrix ---- */

static void _ss_build_interp_matrix(double* mat, const ControlPoint* pts, int n_pts,
                                     int table_size) {
    /* Query points: phase mapped to 2D (x = phase, y = 0) */
    const double eps = 1e-6;
    for (int i = 0; i < table_size; i++) {
        double qx = -1.0 + 2.0 * i / (double)table_size;
        double qy = 0.0;
        double sum = 0.0;
        /* First pass: compute weights */
        double* weights = (double*)malloc((size_t)n_pts * sizeof(double));
        for (int j = 0; j < n_pts; j++) {
            double dx = qx - pts[j].x;
            double dy = qy - pts[j].y;
            double d2 = dx * dx + dy * dy;
            weights[j] = 1.0 / (d2 + eps);
            sum += weights[j];
        }
        for (int j = 0; j < n_pts; j++) {
            mat[i * n_pts + j] = weights[j] / sum;
        }
        free(weights);
    }
}

/* ---- Internal: Minimal least-squares solver (normal equations, Gauss-Jordan) ---- */

/* Solve (A^T A + λI) x = A^T y for x, where A is (rows × cols). */
static void _ss_lstsq(const double* A, const double* y, int rows, int cols,
                       double lambda, double* x_out) {
    /* Build ATA = A^T A + λI  (cols × cols) */
    double* ATA = (double*)calloc((size_t)cols * cols, sizeof(double));
    double* ATy = (double*)calloc((size_t)cols, sizeof(double));

    for (int i = 0; i < cols; i++) {
        for (int j = 0; j < cols; j++) {
            double s = 0.0;
            for (int k = 0; k < rows; k++) {
                s += A[k * cols + i] * A[k * cols + j];
            }
            ATA[i * cols + j] = s;
        }
        ATA[i * cols + i] += lambda;
        double s = 0.0;
        for (int k = 0; k < rows; k++) {
            s += A[k * cols + i] * y[k];
        }
        ATy[i] = s;
    }

    /* Gauss-Jordan elimination on augmented matrix [ATA | ATy] */
    for (int col = 0; col < cols; col++) {
        /* Find pivot */
        int max_row = col;
        double max_val = fabs(ATA[col * cols + col]);
        for (int row = col + 1; row < cols; row++) {
            double v = fabs(ATA[row * cols + col]);
            if (v > max_val) { max_val = v; max_row = row; }
        }
        /* Swap rows */
        if (max_row != col) {
            for (int j = 0; j < cols; j++) {
                double tmp = ATA[col * cols + j];
                ATA[col * cols + j] = ATA[max_row * cols + j];
                ATA[max_row * cols + j] = tmp;
            }
            double tmp = ATy[col]; ATy[col] = ATy[max_row]; ATy[max_row] = tmp;
        }
        /* Eliminate */
        double pivot = ATA[col * cols + col];
        if (fabs(pivot) < 1e-15) pivot = 1e-15;
        for (int j = 0; j < cols; j++) ATA[col * cols + j] /= pivot;
        ATy[col] /= pivot;
        for (int row = 0; row < cols; row++) {
            if (row == col) continue;
            double factor = ATA[row * cols + col];
            for (int j = 0; j < cols; j++) {
                ATA[row * cols + j] -= factor * ATA[col * cols + j];
            }
            ATy[row] -= factor * ATy[col];
        }
    }
    memcpy(x_out, ATy, (size_t)cols * sizeof(double));
    free(ATA);
    free(ATy);
}

/* ---- Internal: Standard waveform generators ---- */

static double _ss_gen_sine(int i, int n) {
    (void)n;
    return sin(2.0 * SS_PI * i / 2048.0);
}

static double _ss_gen_saw(int i, int n) {
    return 2.0 * (double)i / (double)n - 1.0;
}

static double _ss_gen_square(int i, int n) {
    return ((double)i / (double)n < 0.5) ? 1.0 : -1.0;
}

static double _ss_gen_triangle(int i, int n) {
    double t = (double)i / (double)n;
    return 4.0 * fabs(t - 0.5) - 1.0;
}

/* ---- Public API implementation ---- */

void spline_wavetable_init(SplineWavetable* swt, int table_size, int n_control_points) {
    swt->n_points = n_control_points;
    swt->table_size = table_size;
    swt->points = (ControlPoint*)malloc((size_t)n_control_points * sizeof(ControlPoint));
    swt->table = (double*)calloc((size_t)table_size, sizeof(double));
    swt->interp_matrix = (double*)malloc((size_t)table_size * (size_t)n_control_points * sizeof(double));

    _ss_build_lattice(swt->points, n_control_points);
    _ss_build_interp_matrix(swt->interp_matrix, swt->points, n_control_points, table_size);
}

void spline_wavetable_free(SplineWavetable* swt) {
    free(swt->points);
    free(swt->table);
    free(swt->interp_matrix);
    swt->points = NULL;
    swt->table = NULL;
    swt->interp_matrix = NULL;
    swt->n_points = 0;
    swt->table_size = 0;
}

void spline_wavetable_set_values(SplineWavetable* swt, const double* values, int n) {
    for (int i = 0; i < n && i < swt->n_points; i++) {
        swt->points[i].value = values[i];
    }
}

void spline_wavetable_reconstruct(SplineWavetable* swt) {
    for (int i = 0; i < swt->table_size; i++) {
        double s = 0.0;
        for (int j = 0; j < swt->n_points; j++) {
            s += swt->interp_matrix[i * swt->n_points + j] * swt->points[j].value;
        }
        swt->table[i] = s;
    }
}

float spline_wavetable_sample(const SplineWavetable* swt, float phase) {
    float pos = phase * (float)swt->table_size;
    int idx = (int)pos % swt->table_size;
    if (idx < 0) idx += swt->table_size;
    int idx_next = (idx + 1) % swt->table_size;
    float frac = pos - (float)(int)pos;
    return (float)(swt->table[idx] * (1.0 - frac) + swt->table[idx_next] * frac);
}

void spline_morph(const SplineWavetable* a, const SplineWavetable* b, float t, SplineWavetable* out) {
    int n = a->n_points < b->n_points ? a->n_points : b->n_points;
    for (int i = 0; i < n; i++) {
        out->points[i].value = (1.0 - (double)t) * a->points[i].value + (double)t * b->points[i].value;
    }
    spline_wavetable_reconstruct(out);
}

static void _ss_fit_preset(SplineWavetable* swt, double (*gen)(int, int)) {
    double* target = (double*)malloc((size_t)swt->table_size * sizeof(double));
    for (int i = 0; i < swt->table_size; i++) {
        target[i] = gen(i, swt->table_size);
    }
    double* values = (double*)malloc((size_t)swt->n_points * sizeof(double));
    _ss_lstsq(swt->interp_matrix, target, swt->table_size, swt->n_points, 1e-4, values);
    spline_wavetable_set_values(swt, values, swt->n_points);
    spline_wavetable_reconstruct(swt);
    free(target);
    free(values);
}

void spline_preset_sine(SplineWavetable* swt)     { _ss_fit_preset(swt, _ss_gen_sine); }
void spline_preset_saw(SplineWavetable* swt)      { _ss_fit_preset(swt, _ss_gen_saw); }
void spline_preset_square(SplineWavetable* swt)   { _ss_fit_preset(swt, _ss_gen_square); }
void spline_preset_triangle(SplineWavetable* swt) { _ss_fit_preset(swt, _ss_gen_triangle); }

float* spline_wavetable_render(const SplineWavetable* swt, float frequency,
                               float duration, int sample_rate, int* out_n_samples) {
    int n_samples = (int)((float)sample_rate * duration);
    *out_n_samples = n_samples;
    float* output = (float*)malloc((size_t)n_samples * sizeof(float));
    double phase_inc = (double)frequency * (double)swt->table_size / (double)sample_rate;
    double phase = 0.0;
    for (int i = 0; i < n_samples; i++) {
        int idx = (int)phase % swt->table_size;
        if (idx < 0) idx += swt->table_size;
        double frac = phase - (double)(int)phase;
        int idx_next = (idx + 1) % swt->table_size;
        output[i] = (float)(swt->table[idx] * (1.0 - frac) + swt->table[idx_next] * frac);
        phase += phase_inc;
    }
    return output;
}

double spline_reconstruction_error(const SplineWavetable* swt, const double* target, int target_len) {
    int n = swt->table_size < target_len ? swt->table_size : target_len;
    double sum = 0.0;
    for (int i = 0; i < n; i++) {
        double d = swt->table[i] - target[i];
        sum += d * d;
    }
    return sqrt(sum / (double)n);
}

#endif /* SPLINE_SYNTH_IMPLEMENTATION */

#endif /* SPLINE_SYNTH_H */
