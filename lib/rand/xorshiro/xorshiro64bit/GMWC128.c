/*  Written in 2021 by Sebastiano Vigna (vigna@acm.org)

To the extent possible under law, the author has dedicated all copyright
and related and neighboring rights to this software to the public domain
worldwide.

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR
IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE. */

#include <stdint.h>
#include <strings.h>

/* This is a Goresky-Klapper generalized multiply-with-carry generator
   (see their paper "Efficient Multiply-with-Carry Random Number
   Generators with Maximal Period", ACM Trans. Model. Comput. Simul.,
   13(4), p. 310-321, 2003) with period approximately 2^127. While in
   general slower than a scrambled linear generator, it is an excellent
   generator based on congruential arithmetic.

   As all MWC generators, it simulates a multiplicative LCG with prime
   modulus m = 0xff002aae7d81a646007d084a4d80885f and multiplier given by
   the inverse of 2^64 modulo m. Note that the major difference with
   standard (C)MWC generators is that the modulus has a more general form.
   This additional freedom in the choice of the modulus fixes some of the
   theoretical issues of (C)MWC generators, at the price of one 128-bit
   multiplication, one 64-bit multiplication, and one 128-bit sum.
*/

#define GMWC_MINUSA0 0x7d084a4d80885f
#define GMWC_A0INV 0x9b1eea3792a42c61
#define GMWC_A1 0xff002aae7d81a646

/* The state must be initialized so that GMWC_MINUS_A0 <= c <= GMWC_A1.
   For simplicity, we suggest to set c = 1 and x to a 64-bit seed. */
uint64_t x, c;

uint64_t inline next() {
	const __uint128_t t = GMWC_A1 * (__uint128_t)x + c;
	x = GMWC_A0INV * (uint64_t)t;
	c = (t + GMWC_MINUSA0 * (__uint128_t)x) >> 64;
	return x;
}


/* The following jump functions use a minimal multiprecision library. */

#define MP_SIZE 3
#include "mp.c"

static uint64_t mod[MP_SIZE] = { GMWC_MINUSA0, GMWC_A1 };
static __uint128_t mod128 = ((__uint128_t)GMWC_A1 << 64) + GMWC_MINUSA0;


/* This is the jump function for the generator. It is equivalent
   to 2^64 calls to next(); it can be used to generate 2^64
   non-overlapping subsequences for parallel computations.

   Equivalent C++ Boost multiprecision code:

   cpp_int b = cpp_int(1) << 64;
   cpp_int m = GMWC_A1 * b + GMWC_MINUSA0;
   cpp_int r = cpp_int("0xeff1cf6268db2dd61f03b9690dc51b2f");
   cpp_int t = ((m + c * b - GMWC_MINUSA0 * cpp_int(x)) * r) % m;
   x = uint64_t(t * GMWC_A0INV);
   c = uint64_t((t + GMWC_MINUSA0 * cpp_int(x)) >> 64);
*/

void jump(void) {
	static uint64_t jump[MP_SIZE] = { 0x1f03b9690dc51b2f, 0xeff1cf6268db2dd6 };
	const __uint128_t cc = (__uint128_t)c << 64;
	const __uint128_t xx = GMWC_MINUSA0 * (__uint128_t)x;
	const __uint128_t s = cc >= xx ? cc - xx : (mod128 - xx) + cc;
	uint64_t state[MP_SIZE] = { (uint64_t)s, (uint64_t)(s >> 64) };
	mp_mul(state, jump, mod);
	x = GMWC_A0INV * state[0];
	c = ((((__uint128_t)state[1] << 64) + state[0]) + GMWC_MINUSA0 * (__uint128_t)x) >> 64;
}


/* This is the long-jump function for the generator. It is equivalent to
   2^96 calls to next(); it can be used to generate 2^32 starting points,
   from each of which jump() will generate 2^32 non-overlapping
   subsequences for parallel distributed computations. 
   
   Equivalent C++ Boost multiprecision code:

   cpp_int b = cpp_int(1) << 64;
   cpp_int m = GMWC_A1 * b + GMWC_MINUSA0;
   cpp_int r = cpp_int("0xa86e3099c37bf0f8aca58a622476481a");
   cpp_int t = ((m + c * b - GMWC_MINUSA0 * cpp_int(x)) * r) % m;
   x = uint64_t(t * GMWC_A0INV);
   c = uint64_t((t + GMWC_MINUSA0 * cpp_int(x)) >> 64);
*/

void long_jump(void) {
	static uint64_t long_jump[MP_SIZE] = { 0xaca58a622476481a, 0xa86e3099c37bf0f8 };
	const __uint128_t cc = (__uint128_t)c << 64;
	const __uint128_t xx = GMWC_MINUSA0 * (__uint128_t)x;
	const __uint128_t s = cc >= xx ? cc - xx : (mod128 - xx) + cc;
	uint64_t state[MP_SIZE] = { (uint64_t)s, (uint64_t)(s >> 64) };
	mp_mul(state, long_jump, mod);
	x = GMWC_A0INV * state[0];
	c = ((((__uint128_t)state[1] << 64) + state[0]) + (__uint128_t)GMWC_MINUSA0 * x) >> 64;
}


/* The following arbitrary-jump function uses modular exponentiation. The
   per-step LCG multiplier is A = b^-1 mod m; for a Goresky-Klapper
   generator m = GMWC_A1 * b + GMWC_MINUSA0 has no special form, so A is
   given explicitly below. Jumping ahead by n steps multiplies the LCG
   state by A^n mod m. */

static uint64_t base[MP_SIZE] = { 0xd918f9baa1e641df, 0x9a83e52a288e7fba };   // A = b^-1 mod m

static void jumpmul(const uint64_t * const r) {
	const __uint128_t cc = (__uint128_t)c << 64;
	const __uint128_t xx = GMWC_MINUSA0 * (__uint128_t)x;
	const __uint128_t s = cc >= xx ? cc - xx : (mod128 - xx) + cc;
	uint64_t state[MP_SIZE] = { (uint64_t)s, (uint64_t)(s >> 64) };
	mp_mul(state, r, mod);
	x = GMWC_A0INV * state[0];
	c = ((((__uint128_t)state[1] << 64) + state[0]) + GMWC_MINUSA0 * (__uint128_t)x) >> 64;
}

/* This is the arbitrary-jump function for the generator expressed as c * 2^e.
   It is equivalent to c * 2^e calls to next(); for example, jump_ce(1, 64) is
   equivalent to jump() and jump_ce(1, 96) is equivalent to long_jump().
   Expressing the distance as c * 2^e makes it possible to request both ordinary
   counts (jump_ce(k, 0)) and multiples of power-of-two jumps without handling
   multiple-precision integers.

   Equivalent C++ Boost multiprecision code (carry is the generator's c):

   cpp_int b = cpp_int(1) << 64;
   cpp_int m = GMWC_A1 * b + GMWC_MINUSA0;
   cpp_int A("0x9a83e52a288e7fbad918f9baa1e641df");   // = b^-1 mod m
   cpp_int r = powm(A, cpp_int(c) << e, m);           // A^(c * 2^e) mod m
   cpp_int t = ((m + carry * b - GMWC_MINUSA0 * cpp_int(x)) * r) % m;
   x = uint64_t(t * GMWC_A0INV);
   carry = uint64_t((t + GMWC_MINUSA0 * cpp_int(x)) >> 64);
*/

void jump_ce(uint64_t c, uint32_t e) {
	uint64_t r[MP_SIZE];
	mp_powmod(r, base, c, mod);
	while (e--) mp_mul(r, r, mod);
	jumpmul(r);
}

/* This is the general arbitrary-jump function for the generator. It is
   equivalent to n calls to next(), where n = jump[0] + jump[1] * 2^64 + ... is
   the little-endian integer held in the MP_SIZE - 1 words of jump. Unlike
   jump_ce(), it can express any jump distance. For the jump to be meaningful, n
   should be smaller than the period (approximately 2^127).

   Equivalent C++ Boost multiprecision code (carry is the generator's c):

   cpp_int b = cpp_int(1) << 64;
   cpp_int m = GMWC_A1 * b + GMWC_MINUSA0;
   cpp_int A("0x9a83e52a288e7fbad918f9baa1e641df");   // = b^-1 mod m
   cpp_int r = powm(A, n, m);                         // A^n mod m
   cpp_int t = ((m + carry * b - GMWC_MINUSA0 * cpp_int(x)) * r) % m;
   x = uint64_t(t * GMWC_A0INV);
   carry = uint64_t((t + GMWC_MINUSA0 * cpp_int(x)) >> 64);
*/

void jump_n(const uint64_t jump[MP_SIZE - 1]) {
	uint64_t r[MP_SIZE];
	mp_powmod_arr(r, base, jump, MP_SIZE - 1, mod);
	jumpmul(r);
}
