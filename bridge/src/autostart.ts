import { execSync, spawn } from "child_process";
import { existsSync, mkdirSync, writeFileSync, readFileSync, unlinkSync } from "fs";
import { homedir } from "os";
import { join, resolve } from "path";

const BRIDGE_DIR = join(homedir(), ".claudecodemobile-bridge");
const LABEL = "dev.luch.claudecodemobile-bridge";
const PLIST_PATH = join(homedir(), "Library/LaunchAgents", `${LABEL}.plist`);

function ensureDir(dir: string): void {
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

function getNodePath(): string {
  try {
    return execSync("which node", { encoding: "utf-8" }).trim();
  } catch {
    return "/usr/local/bin/node";
  }
}

function getBridgeScript(): string {
  return resolve(join(import.meta.url.replace("file://", ""), "..", "..", "dist", "index.js"));
}

function buildPlist(projectPath: string): string {
  const nodePath = getNodePath();
  const scriptPath = getBridgeScript();
  const logDir = join(BRIDGE_DIR, "logs");
  ensureDir(logDir);
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${nodePath}</string>
    <string>${scriptPath}</string>
    <string>--path</string>
    <string>${projectPath}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${join(logDir, "stdout.log")}</string>
  <key>StandardErrorPath</key>
  <string>${join(logDir, "stderr.log")}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/usr/local/bin:/opt/homebrew/bin:${homedir()}/.local/bin:${homedir()}/.claude/bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
`;
}

export function installAutostart(projectPath: string): void {
  if (process.platform !== "darwin") {
    console.log("[bridge] Autostart only supported on macOS for now.");
    return;
  }
  // Unload if already loaded
  try {
    execSync(`launchctl unload "${PLIST_PATH}" 2>/dev/null`, { encoding: "utf-8" });
  } catch { /* ignore */ }

  const plistContent = buildPlist(projectPath);
  ensureDir(join(homedir(), "Library/LaunchAgents"));
  writeFileSync(PLIST_PATH, plistContent, "utf-8");

  try {
    execSync(`launchctl load "${PLIST_PATH}"`, { encoding: "utf-8" });
    console.log(`[bridge] ✅ Autostart installed: ${LABEL}`);
  } catch (err) {
    console.error("[bridge] Failed to load LaunchAgent:", err);
  }
}

export function uninstallAutostart(): void {
  if (process.platform !== "darwin") return;
  try {
    execSync(`launchctl unload "${PLIST_PATH}" 2>/dev/null`, { encoding: "utf-8" });
  } catch { /* ignore */ }
  try {
    if (existsSync(PLIST_PATH)) unlinkSync(PLIST_PATH);
    console.log(`[bridge] Autostart removed: ${LABEL}`);
  } catch { /* ignore */ }
}
