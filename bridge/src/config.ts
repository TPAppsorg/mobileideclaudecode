import { existsSync, mkdirSync, readFileSync, writeFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";

const CONFIG_DIR = join(homedir(), ".claudecodemobile-bridge");
const CONFIG_FILE = join(CONFIG_DIR, "config.json");

export interface BridgeConfig {
  supabaseUrl: string;
  supabaseAnonKey: string;
  pairId: string | null;
  pairCode: string | null;
  projectPath: string | null;
  port: number;
  clientType: string;
}

interface SavedConfig {
  pairId?: string;
  pairCode?: string;
  projectPath?: string;
}

function loadSavedConfig(): SavedConfig {
  try {
    if (!existsSync(CONFIG_FILE)) return {};
    return JSON.parse(readFileSync(CONFIG_FILE, "utf-8")) as SavedConfig;
  } catch {
    return {};
  }
}

export function saveConfig(updates: Partial<SavedConfig>): void {
  const merged = { ...loadSavedConfig(), ...updates };
  if (!existsSync(CONFIG_DIR)) mkdirSync(CONFIG_DIR, { recursive: true });
  writeFileSync(CONFIG_FILE, JSON.stringify(merged, null, 2), "utf-8");
}

export function getConfig(options: { path?: string; port?: number }): BridgeConfig {
  const saved = loadSavedConfig();

  const supabaseUrl = process.env.SUPABASE_URL || 'https://dmlrznfuccnlpafprbxu.supabase.co';
  const supabaseAnonKey = process.env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRtbHJ6bmZ1Y2NubHBhZnByYnh1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg5NTUyNzksImV4cCI6MjA5NDUzMTI3OX0.NqOvxYOQj9Iu_ksWAS8TGgFnu6fQ5DSeO7Dm4LUa-i8';

  return {
    supabaseUrl,
    supabaseAnonKey,
    pairId: saved.pairId ?? null,
    pairCode: saved.pairCode || null,
    projectPath: options.path || process.cwd(),
    port: options.port || 38476,
    clientType: process.env.BRIDGE_CLIENT_TYPE || "claudecodemobile",
  };
}
