import fs from "node:fs";
import { homedir } from "node:os";
import path from "node:path";

/** Same directory as `config.json` — keeps all bridge machine state in one place. */
const BRIDGE_DIR = path.join(homedir(), ".claudecodemobile-bridge");
const STORAGE_FILE = path.join(BRIDGE_DIR, "supabase-auth-storage.json");

function readMap(): Record<string, string> {
  try {
    const raw = fs.readFileSync(STORAGE_FILE, "utf8");
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
    return parsed as Record<string, string>;
  } catch {
    return {};
  }
}

function writeMap(m: Record<string, string>): void {
  if (!fs.existsSync(BRIDGE_DIR)) {
    fs.mkdirSync(BRIDGE_DIR, { recursive: true });
  }
  const tmp = `${STORAGE_FILE}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(m), { encoding: "utf8", mode: 0o600 });
  fs.renameSync(tmp, STORAGE_FILE);
  try {
    fs.chmodSync(STORAGE_FILE, 0o600);
  } catch {
    // ignore chmod failures on exotic FS
  }
}

/**
 * File-backed storage for `@supabase/supabase-js` so the bridge keeps the same
 * anonymous auth.uid across Terminal restarts.
 */
export const bridgeAuthFileStorage = {
  getItem(key: string): string | null {
    const v = readMap()[key];
    return typeof v === "string" ? v : null;
  },
  setItem(key: string, value: string): void {
    const m = readMap();
    m[key] = value;
    writeMap(m);
  },
  removeItem(key: string): void {
    const m = readMap();
    delete m[key];
    writeMap(m);
  },
};

export function isBridgeAuthPersistenceDisabled(): boolean {
  const raw = process.env.BRIDGE_PERSIST_SUPABASE_SESSION;
  if (!raw) return false;
  return /^(0|false|no|off)$/i.test(raw.trim());
}
