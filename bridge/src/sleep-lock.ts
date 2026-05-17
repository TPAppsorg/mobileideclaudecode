import { ChildProcess, spawn } from "child_process";

let caffeinate: ChildProcess | null = null;

export function acquireSleepLock(): void {
  if (caffeinate) return;
  if (process.platform !== "darwin") {
    return;
    return;
  }
  try {
    caffeinate = spawn("caffeinate", ["-dis"], {
      stdio: "ignore",
      detached: true,
    });
    caffeinate.unref();

  } catch (err) {
    console.warn("[bridge] Failed to acquire sleep-lock:", err);
  }
}

export function releaseSleepLock(): void {
  if (!caffeinate) return;
  try {
    caffeinate.kill("SIGTERM");

  } catch {
    // ignore
  }
  caffeinate = null;
}
