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
   13(4), p. 310-321, 2003) with period approximately 2^255. While in
   general slower than a scrambled linear generator, it is an excellent
   generator based on congruential arithmetic.

   As all MWC generators, it simulates a multiplicative LCG with prime
   modulus m = 0xff963a86efd088a2000000000000000000000000000000000054c3da46afb70f 
   and multiplier given by the inverse of 2^64 modulo m. Note that the
   major difference with (C)MWC generators is that the modulus has a more
   general form. This additional freedom in the choice of the modulus
   fixes some of the theoretical issues of (C)MWC generators, at the price
   of one 128-bit multiplication, one 64-bit multiplication, and one
   128-bit sum.
*/

#define GMWC_MINUSA0 0x54c3da46afb70f
#define GMWC_A0INV 0xbbf397e9a69da811
#define GMWC_A3 0xff963a86efd088a2

/* The state must be initialized so that GMWC_MINUS_A0 <= c <= GMWC_A3.
   For simplicity, we suggest to set c = 1 and x, y, z to a 192-bit seed. */
uint64_t x, y, z, c;

uint64_t inline next() {
	const __uint128_t t = GMWC_A3 * (__uint128_t)x + c;
	x = y;
	y = z;
	z = GMWC_A0INV * (uint64_t)t;
	c = (t + GMWC_MINUSA0 * (__uint128_t)z) >> 64;
	return z;
}


/* The following jump functions use a minimal multiprecision library. */

#define MP_SIZE 5
#include "mp.c"

static uint64_t mod[MP_SIZE] = { GMWC_MINUSA0, 0, 0, GMWC_A3 };
static uint64_t minusa0[MP_SIZE] = { GMWC_MINUSA0 };
// (-GMWC_MINUSA0)^-1 mod 2^192. This is used to recover x, y, z.
static uint64_t rec[MP_SIZE] = { 0xbbf397e9a69da811, 0xc3641cd8c2367132, 0xec9c73821433a23d };


/* This is the jump function for the generator. It is equivalent
   to 2^128 calls to next(); it can be used to generate 2^128
   non-overlapping subsequences for parallel computations.

   Equivalent C++ Boost multiprecision code:

   cpp_int b = cpp_int(1) << 64;
   cpp_int b3 = b * b * b;
   cpp_int m = GMWC_A3 * b3 + GMWC_MINUSA0;
   cpp_int r = cpp_int("0x7f37803efa1e1fa0b6e0bc8a24046dc4f12f5272b6224185e5daa67441bb11e8");
   cpp_int s = ((m + c * b3 - GMWC_MINUSA0 * (x + y * b + z * b * b)) * r) % m;

   cpp_int xyz = s * cpp_int("0xec9c73821433a23dc3641cd8c2367132bbf397e9a69da811");
   x = uint64_t(xyz);
   y = uint64_t(xyz >> 64);
   z = uint64_t(xyz >> 128);
   c = uint64_t((s + (xyz % b3) * GMWC_MINUSA0) >> 192);
*/

void jump(void) {
	static uint64_t jump[MP_SIZE] = { 0xe5daa67441bb11e8, 0xf12f5272b6224185, 0xb6e0bc8a24046dc4, 0x7f37803efa1e1fa0};

	uint64_t state[MP_SIZE] = { 0, 0, 0, c };
	uint64_t xyz[MP_SIZE] = { x, y, z };
	mp_mul(xyz, minusa0, NULL);
	mp_sub(state, xyz, mod);
	mp_mul(state, jump, mod);
	memcpy(xyz, state, sizeof xyz);
	mp_mul(xyz, rec, NULL);

	x = xyz[0];
	y = xyz[1];
	z = xyz[2];
	xyz[3] = xyz[4] = 0;
	mp_mul(xyz, minusa0, NULL);
	mp_add(state, xyz, NULL);
	c = state[3];
}


/* This is the long-jump function for the generator. It is equivalent to
   2^192 calls to next(); it can be used to generate 2^64 starting points,
   from each of which jump() will generate 2^64 non-overlapping
   subsequences for parallel distributed computations.
   
   Equivalent C++ Boost multiprecision code:

   cpp_int b = cpp_int(1) << 64;
   cpp_int b3 = b * b * b;
   cpp_int m = GMWC_A3 * b3 + GMWC_MINUSA0;
   cpp_int r = cpp_int("0x4ac54a5962a2cc857261a61127b93d83a28e7b70072f6082ccb6a9c9ec62a812");
   cpp_int s = ((m + c * b3 - GMWC_MINUSA0 * (x + y * b + z * b * b)) * r) % m;

   cpp_int xyz = s * cpp_int("0xec9c73821433a23dc3641cd8c2367132bbf397e9a69da811");
   x = uint64_t(xyz);
   y = uint64_t(xyz >> 64);
   z = uint64_t(xyz >> 128);
   c = uint64_t((s + (xyz % b3) * GMWC_MINUSA0) >> 192);
*/

void long_jump(void) {
	static uint64_t long_jump[MP_SIZE] = { 0xccb6a9c9ec62a812, 0xa28e7b70072f6082, 0x7261a61127b93d83, 0x4ac54a5962a2cc85};

	uint64_t state[MP_SIZE] = { 0, 0, 0, c };
	uint64_t xyz[MP_SIZE] = { x, y, z };
	mp_mul(xyz, minusa0, NULL);
	mp_sub(state, xyz, mod);
	mp_mul(state, long_jump, mod);
	memcpy(xyz, state, sizeof xyz);
	mp_mul(xyz, rec, NULL);

	x = xyz[0];
	y = xyz[1];
	z = xyz[2];
	xyz[3] = xyz[4] = 0;
	mp_mul(xyz, minusa0, NULL);
	mp_add(state, xyz, NULL);
	c = state[3];
}


/* The following arbitrary-jump function uses modular exponentiation. The
   per-step LCG multiplier is A = b^-1 mod m; for a Goresky-Klapper
   generator m = GMWC_A3 * b^3 + GMWC_MINUSA0 has no special form, so A is
   given explicitly below. Jumping ahead by n steps multiplies the LCG
   state by A^n mod m. */

static uint64_t base[MP_SIZE] = { 0x003e3bb8a6b6a012, 0, 0x40cea5459ddd62c2, 0xbba5f00501dca3e5 };   // A = b^-1 mod m

static void jumpmul(const uint64_t * const r) {
	uint64_t state[MP_SIZE] = { 0, 0, 0, c };
	uint64_t xyz[MP_SIZE] = { x, y, z };
	mp_mul(xyz, minusa0, NULL);
	mp_sub(state, xyz, mod);
	mp_mul(state, r, mod);
	memcpy(xyz, state, sizeof xyz);
	mp_mul(xyz, rec, NULL);

	x = xyz[0];
	y = xyz[1];
	z = xyz[2];
	xyz[3] = xyz[4] = 0;
	mp_mul(xyz, minusa0, NULL);
	mp_add(state, xyz, NULL);
	c = state[3];
}

/* This is the arbitrary-jump function for the generator expressed as c * 2^e.
   It is equivalent to c * 2^e calls to next(); for example, jump_ce(1, 128) is
   equivalent to jump() and jump_ce(1, 192) is equivalent to long_jump().
   Expressing the distance as c * 2^e makes it possible to request both ordinary
   counts (jump_ce(k, 0)) and multiples of power-of-two jumps without handling
   multiple-precision integers.

   Equivalent C++ Boost multiprecision code (carry is the generator's c):

   cpp_int b = cpp_int(1) << 64;
   cpp_int b3 = b * b * b;
   cpp_int m = GMWC_A3 * b3 + GMWC_MINUSA0;
   cpp_int A("0xbba5f00501dca3e540cea5459ddd62c20000000000000000003e3bb8a6b6a012");  // = b^-1 mod m
   cpp_int r = powm(A, cpp_int(c) << e, m);                                          // A^(c * 2^e) mod m
   cpp_int s = ((m + carry * b3 - GMWC_MINUSA0 * (x + y * b + z * b * b)) * r) % m;

   cpp_int xyz = s * cpp_int("0xec9c73821433a23dc3641cd8c2367132bbf397e9a69da811");
   x = uint64_t(xyz);
   y = uint64_t(xyz >> 64);
   z = uint64_t(xyz >> 128);
   carry = uint64_t((s + (xyz % b3) * GMWC_MINUSA0) >> 192);
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
   should be smaller than the period (approximately 2^255).

   Equivalent C++ Boost multiprecision code (carry is the generator's c):

   cpp_int b = cpp_int(1) << 64;
   cpp_int b3 = b * b * b;
   cpp_int m = GMWC_A3 * b3 + GMWC_MINUSA0;
   cpp_int A("0xbba5f00501dca3e540cea5459ddd62c20000000000000000003e3bb8a6b6a012");  // = b^-1 mod m
   cpp_int r = powm(A, n, m);                                                        // A^n mod m
   cpp_int s = ((m + carry * b3 - GMWC_MINUSA0 * (x + y * b + z * b * b)) * r) % m;

   cpp_int xyz = s * cpp_int("0xec9c73821433a23dc3641cd8c2367132bbf397e9a69da811");
   x = uint64_t(xyz);
   y = uint64_t(xyz >> 64);
   z = uint64_t(xyz >> 128);
   carry = uint64_t((s + (xyz % b3) * GMWC_MINUSA0) >> 192);
*/

void jump_n(const uint64_t jump[MP_SIZE - 1]) {
	uint64_t r[MP_SIZE];
	mp_powmod_arr(r, base, jump, MP_SIZE - 1, mod);
	jumpmul(r);
}
