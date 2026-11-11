/** Split totalCents across weights proportionally. Parts must sum to totalCents. */
export function allocate(totalCents: number, weights: number[]): number[] {
  const sum = weights.reduce((a, b) => a + b, 0);
  const exact = weights.map((w) => (totalCents * w) / sum);
  const parts = exact.map(Math.floor);
  let remainder = totalCents - parts.reduce((a, b) => a + b, 0);
  const order = weights.map((w, i) => i).filter((i) => weights[i] > 0)
    .sort((a, b) => weights[b] - weights[a] || a - b);
  for (let k = 0; remainder > 0; k = (k + 1) % order.length, remainder--) parts[order[k]] += 1;
  return parts;
}
