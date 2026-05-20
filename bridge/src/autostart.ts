import { execSync } from "child_process";
import { existsSync, mkdirSync, unlinkSync, writeFileSync } from "fs";
import { homedir, platform } from "os";
import { join, resolve } from "path";

const SERVICE_NAME = "dev.luch.claudecodemobile-bridge";
const SYSTEMD_SERVICE_NAME = "claudecodemobile-bridge";
const WIN_TASK_NAME = "ClaudeCodeMobileBridge";

// ---------------------------------------------------------------------------
// Path helpers
// ---------------------------------------------------------------------------

function getMacPlistPath(): string {
  return join(homedir(), "Library", "LaunchAgents", `${SERVICE_NAME}.plist`);
}

function getLinuxServiceDir(): string {
  return join(homedir(), ".config", "systemd", "user");
}

function getLinuxServicePath(): string {
  return join(getLinuxServiceDir(), `${SYSTEMD_SERVICE_NAME}.service`);
}

function getNodePath(): string {
  if (platform() === "win32") {
    try {
      return execSync("where node", { encoding: "utf-8" }).trim().split(/\r?\n/)[0].trim();
    } catch {
      return "node";
    }
  }
  try {
    const shell = platform() === "darwin" ? "/bin/zsh" : "/bin/bash";
    return execSync("which node", { encoding: "utf-8", shell, env: { ...process.env } }).trim();
  } catch {
    return "/usr/local/bin/node";
  }
}

function getBridgeScript(): string {
  return resolve(join(import.meta.url.replace("file://", ""), "..", "..", "dist", "index.js"));
}

// ---------------------------------------------------------------------------
// macOS – LaunchAgent
// ---------------------------------------------------------------------------

function installMac(projectPath?: string): void {
  const logDir = join(homedir(), ".claudecodemobile-bridge");
  if (!existsSync(logDir)) mkdirSync(logDir, { recursive: true });

  const nodePath = getNodePath();
  const scriptPath = getBridgeScript();

  let cmd = `"${nodePath}" "${scriptPath}"`;
  if (projectPath) cmd += ` --path ${projectPath}`;

  // Use login shell so all PATH entries (homebrew, nvm, fnm, etc.) are loaded.
  const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${SERVICE_NAME}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-l</string>
    <string>-c</string>
    <string>${cmd}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${logDir}/bridge.log</string>
  <key>StandardErrorPath</key>
  <string>${logDir}/bridge-error.log</string>
  <key>WorkingDirectory</key>
  <string>${projectPath || homedir()}</string>
</dict>
</plist>`;

  const plistPath = getMacPlistPath();
  const launchAgentsDir = join(homedir(), "Library", "LaunchAgents");
  if (!existsSync(launchAgentsDir)) mkdirSync(launchAgentsDir, { recursive: true });

  writeFileSync(plistPath, plist, "utf-8");
  try {
    execSync(`launchctl bootout gui/$(id -u) "${plistPath}"`, { stdio: "ignore" });
  } catch {
    // ignore – may not be loaded yet
  }
  execSync(`launchctl bootstrap gui/$(id -u) "${plistPath}"`);
}

function uninstallMac(): void {
  const plistPath = getMacPlistPath();
  if (!existsSync(plistPath)) return;
  try {
    execSync(`launchctl bootout gui/$(id -u) "${plistPath}"`, { stdio: "ignore" });
  } catch {
    // ignore
  }
  unlinkSync(plistPath);
}

// ---------------------------------------------------------------------------
// Linux – systemd user service
// ---------------------------------------------------------------------------

function installLinux(projectPath?: string): void {
  const logDir = join(homedir(), ".claudecodemobile-bridge");
  if (!existsSync(logDir)) mkdirSync(logDir, { recursive: true });

  const nodePath = getNodePath();
  const scriptPath = getBridgeScript();
  const nodeDir = nodePath.substring(0, nodePath.lastIndexOf("/"));

  // Build the full PATH so node/npx are reachable from systemd.
  const basePath = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  const envPath = `${nodeDir}:${basePath}`;

  let execStart = `"${nodePath}" "${scriptPath}"`;
  if (projectPath) execStart += ` --path ${projectPath}`;

  const unit = `[Unit]
Description=Claude Code Mobile Bridge
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash -lc '${execStart}'
Restart=always
RestartSec=5
WorkingDirectory=${projectPath || homedir()}
Environment=PATH=${envPath}
StandardOutput=append:${logDir}/bridge.log
StandardError=append:${logDir}/bridge-error.log

[Install]
WantedBy=default.target
`;

  const serviceDir = getLinuxServiceDir();
  if (!existsSync(serviceDir)) mkdirSync(serviceDir, { recursive: true });

  const servicePath = getLinuxServicePath();
  writeFileSync(servicePath, unit, "utf-8");

  execSync("systemctl --user daemon-reload");
  execSync(`systemctl --user enable ${SYSTEMD_SERVICE_NAME}.service`);
  execSync(`systemctl --user restart ${SYSTEMD_SERVICE_NAME}.service`);

  // Enable lingering so the service starts even without an active login session.
  try {
    execSync("loginctl enable-linger");
  } catch {
    // Requires polkit or root – non-fatal.
  }
}

function uninstallLinux(): void {
  const servicePath = getLinuxServicePath();
  if (!existsSync(servicePath)) return;
  try {
    execSync(`systemctl --user stop ${SYSTEMD_SERVICE_NAME}.service`, { stdio: "ignore" });
    execSync(`systemctl --user disable ${SYSTEMD_SERVICE_NAME}.service`, { stdio: "ignore" });
  } catch {
    // ignore
  }
  unlinkSync(servicePath);
  try {
    execSync("systemctl --user daemon-reload", { stdio: "ignore" });
  } catch {
    // ignore
  }
}

// ---------------------------------------------------------------------------
// Windows – Task Scheduler
// ---------------------------------------------------------------------------

function getWinScriptDir(): string {
  return join(process.env.APPDATA || join(homedir(), "AppData", "Roaming"), "ClaudeCodeMobileBridge");
}

function getWinBatPath(): string {
  return join(getWinScriptDir(), "bridge.bat");
}

function getWinVbsPath(): string {
  return join(getWinScriptDir(), "bridge-hidden.vbs");
}

function installWindows(projectPath?: string): void {
  const scriptDir = getWinScriptDir();
  if (!existsSync(scriptDir)) mkdirSync(scriptDir, { recursive: true });

  const logDir = scriptDir;
  const workDir = projectPath || homedir();

  const nodePath = getNodePath();
  const scriptPath = getBridgeScript();

  let cmd = `"${nodePath}" "${scriptPath}"`;
  if (projectPath) cmd += ` --path "${projectPath}"`;

  // .bat launcher with logging
  const bat = `@echo off
cd /d "${workDir}"
${cmd} >> "${logDir}\\bridge.log" 2>> "${logDir}\\bridge-error.log"
`;
  writeFileSync(getWinBatPath(), bat, "utf-8");

  // .vbs wrapper to run hidden (no console window flash)
  const vbs = `Set WshShell = CreateObject("WScript.Shell")
WshShell.Run chr(34) & "${getWinBatPath().replace(/\\/g, "\\")}" & chr(34), 0
Set WshShell = Nothing
`;
  writeFileSync(getWinVbsPath(), vbs, "utf-8");

  // Remove existing task if present
  try {
    execSync(`schtasks /Delete /TN "${WIN_TASK_NAME}" /F`, { stdio: "ignore" });
  } catch {
    // ignore
  }

  // Create scheduled task: runs at logon, restarts on failure
  const schtasksCmd = [
    `schtasks /Create`,
    `/TN "${WIN_TASK_NAME}"`,
    `/TR "wscript.exe \"${getWinVbsPath()}\""`,
    `/SC ONLOGON`,
    `/RL HIGHEST`,
    `/F`,
  ].join(" ");
  execSync(schtasksCmd);

  // Start it now
  try {
    execSync(`schtasks /Run /TN "${WIN_TASK_NAME}"`, { stdio: "ignore" });
  } catch {
    // ignore – may already be running
  }
}

function uninstallWindows(): void {
  try {
    execSync(`schtasks /Delete /TN "${WIN_TASK_NAME}" /F`, { stdio: "ignore" });
  } catch {
    // ignore
  }
  // Kill any running bridge processes
  try {
    execSync('taskkill /F /FI "WINDOWTITLE eq claudecodemobile-bridge*"', { stdio: "ignore" });
  } catch {
    // ignore
  }
  const batPath = getWinBatPath();
  const vbsPath = getWinVbsPath();
  if (existsSync(batPath)) unlinkSync(batPath);
  if (existsSync(vbsPath)) unlinkSync(vbsPath);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export function installAutostart(projectPath?: string): void {
  if (platform() === "darwin") {
    installMac(projectPath);
  } else if (platform() === "linux") {
    installLinux(projectPath);
  } else if (platform() === "win32") {
    installWindows(projectPath);
  }
}

export function uninstallAutostart(): void {
  if (platform() === "darwin") {
    uninstallMac();
  } else if (platform() === "linux") {
    uninstallLinux();
  } else if (platform() === "win32") {
    uninstallWindows();
  }
}

export function isAutostartInstalled(): boolean {
  if (platform() === "darwin") return existsSync(getMacPlistPath());
  if (platform() === "linux") return existsSync(getLinuxServicePath());
  if (platform() === "win32") return existsSync(getWinVbsPath());
  return false;
}
