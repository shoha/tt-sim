// Portable transcendental functions for TerraDerive (card terraform-p1-native, 2026-11-22).
//
// The derive is the authority every peer agrees on, so its digests must match on Windows, Linux
// and macOS (x86_64 and arm64). libm's pow, exp and atan differ in their last bits between those C
// runtimes (docs/systems/scatter.md: native parity is per platform), so the derive never calls
// them. Each function here is a range reduction and a fixed polynomial over + - * / only, which
// IEEE 754 rounds exactly the same everywhere, given the build's -ffp-contract=off and no
// fast-math (native/SConstruct). std::sqrt, std::floor, std::frexp and std::ldexp are exact by the
// standard and stay allowed. Accuracy is about 1e-15 relative, far below the float32 the arrays
// hold; the point is the same bits, not the last ulp.
//
// .github/native/parity.sh runs tests/unit/test_terra_golden.gd on every platform CI builds, so a
// platform that disagrees fails CI. Fix it here, never in the test.
#pragma once

#include <cmath>

namespace terra {

constexpr double DET_LN2_HI = 6.93147180369123816490e-01;
constexpr double DET_LN2_LO = 1.90821492927058770002e-10;
constexpr double DET_LN2 = 6.93147180559945309417e-01;
constexpr double DET_SQRT_HALF = 7.07106781186547524401e-01;
constexpr double DET_PI_2 = 1.57079632679489661923;
constexpr double DET_PI_6 = 5.23598775598298873077e-01;
constexpr double DET_SQRT3 = 1.73205080756887729353;
constexpr double DET_TAN_PI_12 = 2.67949192431122706473e-01;

/// e^x for x in [-700, 700] (clamped there): x = k ln2 + r with |r| <= ln2 / 2, e^r by its Taylor
/// series to r^16 (the remainder is under 1e-18), then scaled by 2^k exactly.
inline double det_exp(double x) {
	if (!(x == x)) {
		return x;
	}
	x = x < -700.0 ? -700.0 : (x > 700.0 ? 700.0 : x);
	double k = std::floor(x / DET_LN2 + 0.5);
	double r = (x - k * DET_LN2_HI) - k * DET_LN2_LO;
	// Horner from the highest term: 1 + r (1 + r/2 (1 + r/3 (... (1 + r/16)))).
	double p = 1.0;
	for (int n = 16; n >= 1; n--) {
		p = 1.0 + p * (r / double(n));
	}
	return std::ldexp(p, int(k));
}

/// ln x for x > 0 (0 gives -inf, a negative or NaN input NaN): x = m 2^e with m in [sqrt(1/2),
/// sqrt(2)), ln m = 2 atanh(s) with s = (m - 1) / (m + 1), |s| <= 0.1716, by its series to s^23.
inline double det_log(double x) {
	if (!(x > 0.0)) {
		return x == 0.0 ? -HUGE_VAL : NAN;
	}
	if (x == HUGE_VAL) {
		return x;
	}
	int e = 0;
	double m = std::frexp(x, &e); // m in [0.5, 1)
	if (m < DET_SQRT_HALF) {
		m *= 2.0;
		e -= 1;
	}
	double s = (m - 1.0) / (m + 1.0);
	double s2 = s * s;
	double p = 0.0;
	for (int n = 23; n >= 1; n -= 2) {
		p = 1.0 / double(n) + s2 * p;
	}
	double lm = 2.0 * s * p;
	return (double(e) * DET_LN2_HI + lm) + double(e) * DET_LN2_LO;
}

/// b^p for b >= 0 and any finite p: exactly 1 for p == 0 and for b == 1, 0 for b == 0 and p > 0,
/// else exp(p ln b). The profiles of hills and ridges call it with b in [0, 1].
inline double det_pow(double b, double p) {
	if (p == 0.0 || b == 1.0) {
		return 1.0;
	}
	if (b == 0.0) {
		return p > 0.0 ? 0.0 : HUGE_VAL;
	}
	if (b < 0.0) {
		return NAN;
	}
	return det_exp(p * det_log(b));
}

/// atan x: odd, atan x = pi/2 - atan(1/x) past 1, and atan x = pi/6 + atan((x sqrt3 - 1) /
/// (x + sqrt3)) past tan(pi/12), leaving |y| <= 0.268 for the series to y^29.
inline double det_atan(double x) {
	if (!(x == x)) {
		return x;
	}
	bool neg = x < 0.0;
	double a = neg ? -x : x;
	if (a == HUGE_VAL) {
		return neg ? -DET_PI_2 : DET_PI_2;
	}
	bool inv = a > 1.0;
	if (inv) {
		a = 1.0 / a;
	}
	bool shift = a > DET_TAN_PI_12;
	if (shift) {
		a = (a * DET_SQRT3 - 1.0) / (a + DET_SQRT3);
	}
	double a2 = a * a;
	double p = 0.0;
	for (int n = 29; n >= 1; n -= 2) {
		double t = 1.0 / double(n);
		p = ((n / 2) % 2 ? -t : t) + a2 * p;
	}
	double r = a * p;
	if (shift) {
		r += DET_PI_6;
	}
	if (inv) {
		r = DET_PI_2 - r;
	}
	return neg ? -r : r;
}

} // namespace terra
