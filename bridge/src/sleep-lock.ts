import { existsSync } from "node:fs";
import { ChildProcess, execFileSync, spawn } from "node:child_process";

let sleepLockChild: ChildProcess | null = null;

function preventSleepDisabledByEnv(): boolean {
  const raw = process.env.BRIDGE_PREVENT_SLEEP;
  if (!raw) return false;
  return /^(0|false|no|off)$/i.test(raw.trim());
}

function resolveSystemdInhibitPath(): string | null {
  for (const p of ["/usr/bin/systemd-inhibit", "/bin/systemd-inhibit"]) {
    if (existsSync(p)) return p;
  }
  try {
    const out = execFileSync("which", ["systemd-inhibit"], { encoding: "utf8", timeout: 2000 }).trim();
    return out.length > 0 ? out : null;
  } catch {
    return null;
  }
}

/**
 * While the bridge is connected, keep the workstation from idle-sleeping
 * (macOS: `caffeinate`, Linux: `systemd-inhibit`). Windows: unsupported.
 * Disable with `BRIDGE_PREVENT_SLEEP=0`.
 */
export function acquireSleepLock(): void {
  if (sleepLockChild) return;
  if (preventSleepDisabledByEnv()) return;

  if (process.platform === "darwin") {
    try {
      sleepLockChild = spawn("caffeinate", ["-i", "-w", String(process.pid)], {
        stdio: "ignore",
      });
      sleepLockChild.on("error", (err) => {
        console.warn("[bridge] caffeinate failed:", (err as Error).message);
        sleepLockChild = null;
      });
      sleepLockChild.on("exit", () => {
        sleepLockChild = null;
      });
    } catch (err) {
      console.warn("[bridge] Could not start caffeinate:", (err as Error).message);
    }
    return;
  }

  if (process.platform === "linux") {
    const inhibit = resolveSystemdInhibitPath();
    if (!inhibit) return;
    try {
      sleepLockChild = spawn(inhibit, [
        "--what=idle:sleep:handle-lid-switch",
        "--who=claudecodemobile-bridge",
        "--why=Claude Code Mobile bridge session",
        "sh",
        "-c",
        "exec tail -f /dev/null",
      ], { stdio: "ignore" });
      sleepLockChild.on("error", (err) => {
        console.warn("[bridge] systemd-inhibit failed:", (err as Error).message);
        sleepLockChild = null;
      });
      sleepLockChild.on("exit", () => {
        sleepLockChild = null;
      });
    } catch (err) {
      console.warn("[bridge] Could not start systemd-inhibit:", (err as Error).message);
    }
  }
}

export function releaseSleepLock(): void {
  if (!sleepLockChild) return;
  try {
    sleepLockChild.kill("SIGTERM");
  } catch {
    // ignore
  }
  sleepLockChild = null;
}
