export interface Config {
  port: number;
  host: string;
  tls: { enabled: boolean; certPath?: string };
  replicas: number;
}

export type ParseResult = { ok: true; config: Config } | { ok: false; errors: string[] };

export function parseConfig(input: unknown): ParseResult {
  if (typeof input !== "object" || input === null || Array.isArray(input)) {
    return { ok: false, errors: ["config: must be an object"] };
  }
  const o = input as Record<string, unknown>;
  const errors: string[] = [];
  const port = o.port;
  if (!Number.isInteger(port) || (port as number) < 1 || (port as number) > 65535) errors.push("port: must be an integer between 1 and 65535");
  if (typeof o.host !== "string" || o.host.length === 0) errors.push("host: must be a non-empty string");
  const tls = (o.tls ?? {}) as Record<string, unknown>;
  const enabled = tls.enabled === true;
  if (enabled && (typeof tls.certPath !== "string" || tls.certPath.length === 0)) errors.push("tls.certPath: required when tls.enabled is true");
  const replicas = o.replicas ?? 1;
  if (!Number.isInteger(replicas) || (replicas as number) < 1) errors.push("replicas: must be an integer >= 1");
  if (errors.length) return { ok: false, errors };
  const tlsOut: Config["tls"] = { enabled };
  if (typeof tls.certPath === "string") tlsOut.certPath = tls.certPath;
  return { ok: true, config: { port: port as number, host: o.host as string, tls: tlsOut, replicas: replicas as number } };
}
