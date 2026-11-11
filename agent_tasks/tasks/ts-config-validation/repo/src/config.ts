export interface Config {
  port: number;            // integer 1-65535
  host: string;            // non-empty
  tls: { enabled: boolean; certPath?: string }; // certPath required when enabled
  replicas: number;        // integer >= 1, default 1
}

export type ParseResult = { ok: true; config: Config } | { ok: false; errors: string[] };

export function parseConfig(input: unknown): ParseResult {
  throw new Error("not implemented");
}
