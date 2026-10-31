/* dot.c -- dot.l0's loop in C, as Needle's engine would write it,
   for comparison: the same generator, sizes and checksum. */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>
static void filled(uint8_t *b, long n, long seed) {
  for (long i = n - 1; i >= 0; i--) { b[i] = (seed / 65536) % 256; seed = (seed * 1103515245 + 12345) % 2147483648; }
}
int main(void) {
  long n = 768, reps = 50;
  uint8_t *w = malloc(n * n), *x = malloc(n);
  filled(w, n * n, 1); filled(x, n, 7);
  struct timespec a, b; clock_gettime(CLOCK_MONOTONIC, &a);
  long s = 0;
  for (long k = 0; k < reps; k++) {
    long sum = 0;
    for (long r = 0; r < n; r++) {
      int32_t acc = 0;
      for (long j = 0; j < n; j++) acc += (int8_t)w[r * n + j] * (int8_t)x[j];
      sum ^= acc;
    }
    s += sum;
  }
  clock_gettime(CLOCK_MONOTONIC, &b);
  long ns = (b.tv_sec - a.tv_sec) * 1000000000L + (b.tv_nsec - a.tv_nsec);
  printf("checksum %ld, %ld ps per multiply-add\n", s, ns * 1000 / (reps * n * n));
  return 0;
}
