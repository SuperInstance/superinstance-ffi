#include <cstdarg>
#include <cstdint>
#include <cstdlib>
#include <ostream>
#include <new>

extern "C" {

/// Eisenstein integer norm: a² - ab + b²
int64_t si_eisenstein_norm(int32_t a, int32_t b);

/// Laman graph edge count: 2v - 3
int32_t si_laman_edges(int32_t v);

/// Check if a graph with v vertices and e edges is rigid (Laman condition)
bool si_is_rigid(int32_t v, int32_t e);

/// Check holonomy: product of all transforms must equal 1 (identity)
/// Each transform is a packed i64 representing a group element.
/// For simplicity, we check if the cumulative XOR-based hash equals 0 or
/// if the product of signed values equals 1.
bool si_holonomy_check(const int64_t *transforms, uintptr_t len);

/// Quantize a 2D direction to one of 48 evenly-spaced angles (7.5° increments).
/// Returns a u8 in [0, 47].
uint8_t si_pythagorean48_encode(double x, double y);

/// Manhattan distance between two integer vectors.
int64_t si_manhattan_distance(const int32_t *a, const int32_t *b, uintptr_t len);

/// Cascade matching: count matching bytes between query and a single codebook entry.
/// Returns number of matching positions.
int32_t si_cascade_match(const uint8_t *query, const uint8_t *codebook, uintptr_t len);

/// Count how many constraint bounds are violated.
/// vals[i] must be <= bounds[i] for satisfaction.
/// Returns count of violations.
uint8_t si_constraint_check(const double *vals, const double *bounds, uintptr_t n);

/// Linear interpolation along a polyline defined by control points.
/// `pts` is a flat array of 2*n doubles (x0,y0, x1,y1, ...).
/// `t` is in [0, 1], mapping to the full arc length.
/// For simplicity, this does uniform-parameter linear interpolation between segments.
double si_spline_interpolate(const double *pts, double t, uintptr_t n);

/// Deadband filter: if val is within `band` of `center`, return center.
/// Otherwise return val (pass through).
double si_deadband_filter(double val, double center, double band);

}  // extern "C"
