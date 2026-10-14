/*  Written in 2023 by Sebastiano Vigna (vigna@acm.org)

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

/* This is a Marsaglia multiply-with-carry generator with period
   approximately 2^127. It is close in speed to a scrambled linear
   generator, as its only 128-bit operations are a multiplication and sum;
   it is an excellent generator based on congruential arithmetic.

   As all MWC generators, it simulates a multiplicative LCG with
   prime modulus m = 0xffebb71d94fcdaf8ffffffffffffffff and
   multiplier given by the inverse of 2^64 modulo m. The modulus has a
   particular form, which creates some theoretical issues, but at this
   size a generator of this kind passes all known statistical tests,
   except for very large size birthday-spacings tests in three dimensions
   (as predicted from the theory). These failures are unlikely to have
   any impact in practice.

   For a generator of the same type with stronger theoretical guarantees,
   consider a Goresky-Klapper generalized multiply-with-carry generator.

   Alternatively, applying a xorshift to the result (i.e., returning
   x ^ (x << 32) instead of x) will eliminate the birthday-spacings
   failures.

   Note that a previous version had a different MWC_A1. Moreover, now
   the result is computed using the current state.
*/

#define MWC_A1 0xffebb71d94fcdaf9

/* The state must be initialized so that 0 < c < MWC_A1 - 1.
   For simplicity, we suggest to set c = 1 and x to a 64-bit seed. */
uint64_t x, c;

uint64_t inline next() {
	const uint64_t result = x; // Or, result = x ^ (x << 32) (see above)
	const __uint128_t t = MWC_A1 * (__uint128_t)x + c;
	x = t;
	c = t >> 64;
	return result;
}


/* The following jump functions use a minimal multiprecision library. */

#define MP_SIZE 3
#include "mp.c"

static uint64_t mod[MP_SIZE] = { 0xffffffffffffffff, MWC_A1 - 1 };


/* This is the jump function for the generator. It is equivalent
   to 2^64 calls to next(); it can be used to generate 2^64
   non-overlapping subsequences for parallel computations.

   Equivalent C++ Boost multiprecision code:

   cpp_int b = cpp_int(1) << 64;
   cpp_int m = MWC_A1 * b - 1;
   cpp_int r = cpp_int("0x2f65fed2e8400983a72f9a3547208003");
   cpp_int s = ((x + c * b) * r) % m;
   x = uint64_t(s);
   c = uint64_t(s >> 64);
*/

void jump(void) {
	static uint64_t jump[MP_SIZE] = { 0xa72f9a3547208003, 0x2f65fed2e8400983 };
	uint64_t state[MP_SIZE] = { x, c };
	mp_mul(state, jump, mod);
	x = state[0];
	c = state[1];
}


/* This is the long-jump function for the generator. It is equivalent to
   2^96 calls to next(); it can be used to generate 2^32 starting points,
   from each of which jump() will generate 2^32 non-overlapping
   subsequences for parallel distributed computations. 
   
   Equivalent C++ Boost multiprecision code:

   cpp_int b = cpp_int(1) << 64;
   cpp_int m = MWC_A1 * b - 1;
   cpp_int r = cpp_int("0x394649cfd6769c91e6f7814467f3fcdd");
   cpp_int s = ((x + c * b) * r) % m;
   x = uint64_t(s);
   c = uint64_t(s >> 64);
*/

void long_jump(void) {
	static uint64_t long_jump[MP_SIZE] = { 0xe6f7814467f3fcdd, 0x394649cfd6769c91 };
	uint64_t state[MP_SIZE] = { x, c };
	mp_mul(state, long_jump, mod);
	x = state[0];
	c = state[1];
}


/* The following arbitrary-jump function uses modular exponentiation An
   MWC generator with base b = 2^64 and multiplier MWC_A1 simulates a
   multiplicative LCG with modulus m = MWC_A1 * b - 1 whose per-step
   multiplier is A = b^-1 mod m; since MWC_A1 * b = m + 1, we have simply
   A = MWC_A1. Jumping ahead by n steps multiplies the LCG state by A^n
   mod m. */

static uint64_t base[MP_SIZE] = { MWC_A1 };   // A = b^-1 mod m

static void jumpmul(const uint64_t * const r) {
	uint64_t state[MP_SIZE] = { x, c };
	mp_mul(state, r, mod);
	x = state[0];
	c = state[1];
}

/* This is the arbitrary-jump function for the generator expressed as c * 2^e.
   It is equivalent to c * 2^e calls to next(); for example, jump_ce(1, 64) is
   equivalent to jump() and jump_ce(1, 96) is equivalent to long_jump().
   Expressing the distance as c * 2^e makes it possible to request both ordinary
   counts (jump_ce(k, 0)) and multiples of power-of-two jumps without handling
   multiple-precision integers.

   Equivalent C++ Boost multiprecision code (carry is the generator's c):

   cpp_int b = cpp_int(1) << 64;
   cpp_int m = MWC_A1 * b - 1;
   cpp_int A = MWC_A1;                          // = b^-1 mod m
   cpp_int r = powm(A, cpp_int(c) << e, m);     // A^(c * 2^e) mod m
   cpp_int s = ((x + carry * b) * r) % m;
   x = uint64_t(s);
   carry = uint64_t(s >> 64);
*/

void jump_ce(uint64_t c, uint32_t e) {
	uint64_t r[MP_SIZE];
	mp_powmod(r, base, c, mod);
	while (e--) mp_mul(r, r, mod);   // r = (base^c)^(2^e) = base^(c * 2^e) mod m
	jumpmul(r);
}

/* This is the general arbitrary-jump function for the generator. It is
   equivalent to n calls to next(), where n = jump[0] + jump[1] * 2^64 + ... is
   the little-endian integer held in the MP_SIZE - 1 words of jump. Unlike
   jump_ce(), it can express any jump distance. For the jump to be meaningful, n
   should be smaller than the period (approximately 2^127).

   Equivalent C++ Boost multiprecision code (carry is the generator's c):

   cpp_int b = cpp_int(1) << 64;
   cpp_int m = MWC_A1 * b - 1;
   cpp_int A = MWC_A1;                          // = b^-1 mod m
   cpp_int r = powm(A, n, m);                   // A^n mod m
   cpp_int s = ((x + carry * b) * r) % m;
   x = uint64_t(s);
   carry = uint64_t(s >> 64);
*/

void jump_n(const uint64_t jump[MP_SIZE - 1]) {
	uint64_t r[MP_SIZE];
	mp_powmod_arr(r, base, jump, MP_SIZE - 1, mod);
	jumpmul(r);
}
