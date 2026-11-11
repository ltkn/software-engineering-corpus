/** Split totalCents across weights proportionally. Parts must sum to totalCents. */
export function allocate(totalCents: number, weights: number[]): number[] {
  const sum = weights.reduce((a, b) => a + b, 0);
  return weights.map((w) => Math.round((totalCents * w) / sum));
}
