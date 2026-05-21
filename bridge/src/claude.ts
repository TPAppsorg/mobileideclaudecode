import { ChildProcess, execSync, spawn } from "child_process";
import { accessSync, constants, existsSync, readFileSync, realpathSync } from "fs";
import { homedir } from "os";
import { dirname, join } from "path";

// ─── Types ───────────────────────────────────────────────────────────

export interface ClaudeOptions {
  model?: string;
  cwd?: string;
  continueSession?: boolean;
  timeout?: number;
  onChunk?: (delta: string) => void;
}

export interface ClaudeResult {
  output: string;
  exitCode: number;
  killed: boolean;
  sessionId?: string | null;
  stats?: ClaudeResultStats | null;
  errors?: ClaudeStreamError[];
}

export interface ClaudeResultStats {
  totalTokens?: number;
  inputTokens?: number;
  outputTokens?: number;
  durationMs?: number;
  numTurns?: number;
}

export interface ClaudeStreamError {
  message: string;
  code?: string;
  type?: string;
}

type StreamJsonEvent = {
  type?: string;
  subtype?: string;
  role?: string;
  content?: unknown;
  delta?: { text?: string } | boolean;
  message?: string;
  code?: string;
  session_id?: string;
  model?: string;
  tool_name?: string;
  name?: string;
  parameters?: Record<string, unknown>;
  args?: Record<string, unknown>;
  input?: Record<string, unknown>;
  status?: string;
  stats?: Record<string, unknown>;
  duration_ms?: number;
  num_turns?: number;
} & Record<string, unknown>;

// ─── CLI discovery ───────────────────────────────────────────────────

function isWindows(platform: NodeJS.Platform = process.platform): boolean {
  return platform === "win32";
}

function normalizeExecutablePath(p: string): string {
  const trimmed = p.trim();
  if ((trimmed.startsWith('"') && trimmed.endsWith('"')) || (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

function maybeRealpath(p: string): string {
  try { return realpathSync(p); } catch { return p; }
}

function isUsableExecutablePath(p: string, platform: NodeJS.Platform = process.platform): boolean {
  const cleaned = normalizeExecutablePath(p);
  if (!cleaned || !existsSync(cleaned)) return false;
  if (isWindows(platform)) return true;
  try {
    accessSync(cleaned, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function firstUsableCandidate(paths: string[], platform: NodeJS.Platform = process.platform): string | null {
  for (const raw of paths) {
    const p = normalizeExecutablePath(raw);
    if (isUsableExecutablePath(p, platform)) return maybeRealpath(p);
  }
  return null;
}

function preferWindowsClaudeCandidate(paths: string[]): string | null {
  const cleaned = paths.map(normalizeExecutablePath).filter(Boolean);
  if (cleaned.length === 0) return null;
  const rank = (p: string): number => {
    const lower = p.toLowerCase();
    if (lower.endsWith(".cmd")) return 0;
    if (lower.endsWith(".exe")) return 1;
    if (lower.endsWith(".bat")) return 2;
    if (lower.endsWith(".ps1")) return 3;
    return 4;
  };
  return cleaned.sort((a, b) => rank(a) - rank(b))[0] ?? null;
}

function windowsCLICandidatesFromEnv(binaryName: string): string[] {
  const candidates: string[] = [];
  const appData = process.env.APPDATA;
  if (appData) {
    candidates.push(join(appData, "npm", `${binaryName}.cmd`));
    candidates.push(join(appData, "npm", `${binaryName}.exe`));
    candidates.push(join(appData, "npm", `${binaryName}.bat`));
    candidates.push(join(appData, "npm", `${binaryName}.ps1`));
  }
  const localAppData = process.env.LOCALAPPDATA;
  if (localAppData) {
    candidates.push(join(localAppData, "npm", `${binaryName}.cmd`));
    candidates.push(join(localAppData, "npm", `${binaryName}.exe`));
  }
  return candidates;
}

export function findClaudeCLI(platform: NodeJS.Platform = process.platform): string | null {
  const fromEnv = process.env.CLAUDE_CLI_PATH;
  if (fromEnv) {
    const normalized = normalizeExecutablePath(fromEnv);
    if (isUsableExecutablePath(normalized, platform)) return maybeRealpath(normalized);
    console.warn(`[bridge] CLAUDE_CLI_PATH is set but not executable/found: ${normalized}; falling back to PATH.`);
  }

  const binariesToTry = ["claude", "claude-code"];

  for (const bin of binariesToTry) {
    if (isWindows(platform)) {
      try {
        const fromPath = execSync(`where ${bin}`, { encoding: "utf-8", shell: "cmd.exe" })
          .split(/\r?\n/)
          .map((line) => line.trim())
          .filter(Boolean);
        const preferred = preferWindowsClaudeCandidate(fromPath);
        if (preferred && isUsableExecutablePath(preferred, platform)) return maybeRealpath(preferred);
        const fallback = firstUsableCandidate(fromPath, platform);
        if (fallback) return fallback;
      } catch {
        // ignore
      }

      for (const p of windowsCLICandidatesFromEnv(bin)) {
        if (existsSync(p)) return maybeRealpath(p);
      }
    } else {
      try {
        const fromPath = execSync(`which -a ${bin}`, { encoding: "utf-8" })
          .split(/\r?\n/)
          .map((line) => line.trim())
          .filter(Boolean);
        const preferred = firstUsableCandidate(fromPath, platform);
        if (preferred) return preferred;
      } catch {
        // ignore
      }

      const candidates = [
        join(homedir(), ".local", "bin", bin),
        join(homedir(), ".claude", "bin", bin),
        `/usr/local/bin/${bin}`,
        `/opt/homebrew/bin/${bin}`,
      ];
      for (const p of candidates) {
        if (isUsableExecutablePath(p, platform)) return maybeRealpath(p);
      }
    }
  }

  return null;
}

// ─── Spawn Plan for Windows compatibility ────────────────────────────

export interface ClaudeSpawnPlan {
  command: string;
  args: string[];
  detached: boolean;
  windowsVerbatimArguments?: boolean;
}

function commandLineToPassToCmdExe(file: string, args: string[]): string {
  const quote = (raw: string): string => {
    let s = String(raw);
    s = s.replace(/\r?\n/g, " ");
    s = s.replace(/([%^&|<>])/g, "^$1");
    s = s.replace(/"/g, '^"');
    return `"${s}"`;
  };
  return `"${[quote(file), ...args.map(quote)].join(" ")}"`;
}

export function resolveWindowsNpmJsEntry(cmdPath: string): string | null {
  try {
    const content = readFileSync(cmdPath, "utf-8");
    const match = content.match(/"([^"\r\n]+\.js)"/i);
    if (!match) return null;
    const rawPath = match[1];
    const dp0Dir = dirname(cmdPath);
    const candidates = new Set<string>();
    for (const sep of ["\\", "/"]) {
      const expanded = rawPath
        .replace(/%~dp0%/gi, dp0Dir + sep)
        .replace(/%dp0%/gi, dp0Dir + sep);
      candidates.add(expanded.replace(/\\{2,}/g, "\\").replace(/\/{2,}/g, "/"));
    }
    for (const raw of Array.from(candidates)) {
      candidates.add(raw.replace(/\\/g, "/"));
    }
    for (const c of candidates) {
      if (existsSync(c)) return c;
    }
    return null;
  } catch {
    return null;
  }
}

export function resolveClaudeSpawnPlan(
  cliPath: string,
  args: string[],
  platform: NodeJS.Platform = process.platform,
): ClaudeSpawnPlan {
  const normalized = normalizeExecutablePath(cliPath);
  if (!isWindows(platform)) {
    return { command: normalized, args, detached: true };
  }

  const lower = normalized.toLowerCase();
  if (lower.endsWith(".cmd") || lower.endsWith(".bat")) {
    const jsEntry = resolveWindowsNpmJsEntry(normalized);
    if (jsEntry) {
      return {
        command: process.execPath,
        args: [jsEntry, ...args],
        detached: false,
      };
    }
    return {
      command: "cmd.exe",
      args: ["/d", "/s", "/c", commandLineToPassToCmdExe(normalized, args)],
      detached: false,
      windowsVerbatimArguments: true,
    };
  }
  if (lower.endsWith(".ps1")) {
    return {
      command: "powershell.exe",
      args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", normalized, ...args],
      detached: false,
    };
  }
  return { command: normalized, args, detached: false };
}

// ─── Build CLI args ──────────────────────────────────────────────────

export function buildClaudeArgs(prompt: string, options: ClaudeOptions): string[] {
  const args: string[] = [];

  // Print mode (non-interactive)
  args.push("-p");

  // Session continuity
  if (options.continueSession) {
    args.push("-c");
  }

  // Skip permission prompts (YOLO mode for bridge)
  args.push("--dangerously-skip-permissions");

  // Streaming output (--verbose required for stream-json in CLI 2.1+)
  args.push("--verbose", "--output-format", "stream-json");

  // Model selection
  const model = options.model || process.env.CLAUDE_MODEL;
  if (model) {
    args.push("--model", model);
  }

  // Max turns (safety limit)
  const maxTurns = process.env.CLAUDE_MAX_TURNS;
  if (maxTurns) {
    args.push("--max-turns", maxTurns);
  }

  // Budget limit
  const maxBudget = process.env.CLAUDE_MAX_BUDGET_USD;
  if (maxBudget) {
    args.push("--max-budget-usd", maxBudget);
  }

  // Extra user-defined args
  const extra = (process.env.CLAUDE_EXTRA_ARGS || "").trim();
  if (extra) {
    args.push(...extra.split(" ").filter(Boolean));
  }

  // The prompt itself (last argument for -p)
  args.push(prompt);

  return args;
}

// ─── Tool use formatting ─────────────────────────────────────────────

function truncateInline(value: string, max: number): string {
  if (value.length <= max) return value;
  return `${value.slice(0, Math.max(0, max - 1))}…`;
}

function formatToolUseLine(ev: StreamJsonEvent): string {
  const name = (ev.tool_name as string) || (ev.name as string) || "tool";
  const params = (ev.parameters || ev.args || ev.input || {}) as Record<string, unknown>;
  const rawHint =
    (typeof params.command === "string" && params.command) ||
    (typeof params.cmd === "string" && params.cmd) ||
    (typeof params.file_path === "string" && params.file_path) ||
    (typeof params.path === "string" && params.path) ||
    (typeof params.file === "string" && params.file) ||
    (typeof params.description === "string" && params.description) ||
    (typeof params.query === "string" && params.query) ||
    "";
  const hint = rawHint ? ` ${truncateInline(String(rawHint), 100)}` : "";
  return `\n• ${name}${hint}\n`;
}

// ─── Resolve timeout ─────────────────────────────────────────────────

export function resolveClaudeTimeoutMs(explicit?: number): number {
  if (typeof explicit === "number" && explicit > 0) return explicit;
  const fromEnv = parseInt(process.env.CLAUDE_BRIDGE_TIMEOUT_MS || "", 10);
  if (Number.isFinite(fromEnv) && fromEnv > 0) return fromEnv;
  return 0; // no timeout by default
}

// ─── Terminate process tree ──────────────────────────────────────────

export function terminateClaudeProcess(proc: ChildProcess, signal: NodeJS.Signals = "SIGTERM"): void {
  if (proc.killed) return;
  try {
    if (process.platform !== "win32" && proc.pid) {
      process.kill(-proc.pid, signal);
      return;
    }
    proc.kill(signal);
  } catch {
    try { proc.kill(signal); } catch { /* ignore */ }
  }
}

// ─── Run Claude Code CLI ─────────────────────────────────────────────

export function runClaude(
  prompt: string,
  cliPath: string,
  options: ClaudeOptions = {},
): { process: ChildProcess; result: Promise<ClaudeResult> } {
  const args = buildClaudeArgs(prompt, options);
  const timeout = resolveClaudeTimeoutMs(options.timeout);
  const spawnPlan = resolveClaudeSpawnPlan(cliPath, args);

  const proc = spawn(spawnPlan.command, spawnPlan.args, {
    cwd: options.cwd || process.cwd(),
    env: { ...process.env },
    stdio: ["pipe", "pipe", "pipe"],
    detached: spawnPlan.detached,
    windowsVerbatimArguments: spawnPlan.windowsVerbatimArguments === true,
  });

  // Close stdin immediately (non-interactive)
  if (proc.stdin) {
    proc.stdin.end();
  }

  const result = new Promise<ClaudeResult>((resolve) => {
    let visibleOutput = "";
    let stderr = "";
    let killed = false;
    let stdoutBuffer = "";
    let resultStats: ClaudeResultStats | null = null;
    let sessionId: string | null = null;
    const errors: ClaudeStreamError[] = [];

    const timer = timeout > 0
      ? setTimeout(() => {
          killed = true;
          terminateClaudeProcess(proc, "SIGTERM");
        }, timeout)
      : null;

    const appendVisible = (text: string): void => {
      if (!text) return;
      visibleOutput += text;
      try { options.onChunk?.(text); } catch { /* ignore */ }
    };

    const handleStreamEvent = (ev: StreamJsonEvent): void => {
      switch (ev.type) {
        case "system":
          // Extract session_id from init event
          if (ev.subtype === "init" && ev.session_id) {
            sessionId = ev.session_id;
          }
          break;

        case "assistant":
        case "message": {
          // The final "assistant"/"message" event contains the complete text
          // that was already streamed via content_block_delta events.
          // Only use it as a fallback if streaming produced nothing.
          if (visibleOutput) break;

          const msgObj = (typeof ev.message === "object" && ev.message) ? (ev.message as Record<string, any>) : ev;
          if (msgObj.role === "assistant") {
            const content = msgObj.content;
            if (Array.isArray(content)) {
              for (const block of content) {
                if (block.type === "text" && block.text) {
                  appendVisible(block.text);
                } else if (block.type === "thinking" && block.thinking) {
                  appendVisible(`<thinking>\n${block.thinking}\n</thinking>\n`);
                } else if (block.type === "tool_use") {
                  appendVisible(`<thinking>${formatToolUseLine(block as any)}</thinking>`);
                }
              }
            } else if (typeof content === "string") {
              appendVisible(content);
            }
          }
          break;
        }

        case "content_block_delta":
        case "stream_event": {
          // Handle streaming deltas
          const delta = ev.delta;
          if (delta && typeof delta === "object") {
            if ("text" in delta && typeof delta.text === "string") {
              appendVisible(delta.text);
            } else if ("thinking" in delta && typeof delta.thinking === "string") {
              appendVisible(`<thinking>${delta.thinking}</thinking>`);
            }
          }
          break;
        }

        case "tool_call":
        case "tool_use":
          appendVisible(`<thinking>${formatToolUseLine(ev)}</thinking>`);
          break;

        case "tool_result":
          // Suppressed: too noisy, Claude summarizes in the next message
          break;

        case "error": {
          const message = (typeof ev.message === "string" && ev.message) || "Unknown error";
          errors.push({
            message,
            code: typeof ev.code === "string" ? ev.code : undefined,
            type: ev.type,
          });
          break;
        }

        case "result": {
          if (ev.result && typeof ev.result === "string" && !visibleOutput) {
            appendVisible(ev.result);
          }
          const s = (ev.stats || {}) as Record<string, unknown>;
          if (ev.session_id) sessionId = ev.session_id;
          resultStats = {
            totalTokens: typeof s.total_tokens === "number" ? s.total_tokens : undefined,
            inputTokens: typeof s.input_tokens === "number" ? s.input_tokens : undefined,
            outputTokens: typeof s.output_tokens === "number" ? s.output_tokens : undefined,
            durationMs: typeof ev.duration_ms === "number" ? ev.duration_ms : (typeof s.duration_ms === "number" ? s.duration_ms : undefined),
            numTurns: typeof ev.num_turns === "number" ? ev.num_turns : undefined,
          };
          break;
        }

        default:
          // Unknown event type — be lenient
          break;
      }
    };

    const flushLine = (line: string): void => {
      const trimmed = line.trim();
      if (!trimmed) return;
      try {
        const event = JSON.parse(trimmed) as StreamJsonEvent;
        handleStreamEvent(event);
      } catch {
        // Not JSON — stray banner or warning, show to user
        appendVisible(`${line}\n`);
      }
    };

    proc.stdout?.on("data", (data: Buffer) => {
      stdoutBuffer += data.toString("utf-8");
      // NDJSON: split on newlines, keep the last partial line
      const lines = stdoutBuffer.split("\n");
      stdoutBuffer = lines.pop() || "";
      for (const line of lines) flushLine(line);
    });

    proc.stderr?.on("data", (data: Buffer) => {
      stderr += data.toString("utf-8");
    });

    proc.on("close", (code) => {
      if (timer) clearTimeout(timer);
      // Flush trailing partial line
      if (stdoutBuffer.trim()) flushLine(stdoutBuffer);
      stdoutBuffer = "";

      // If stream-json gave explicit errors and no visible text, surface them
      if (!visibleOutput.trim() && errors.length > 0) {
        visibleOutput = errors.map((e) => e.message).filter(Boolean).join("\n");
      }

      // Fallback: bubble up stderr
      if (!visibleOutput && stderr) {
        visibleOutput = `Claude Code CLI error:\n${stderr}`;
      }

      resolve({
        output: visibleOutput || "(empty response)",
        exitCode: code ?? 1,
        killed,
        sessionId,
        stats: resultStats,
        errors,
      });
    });

    proc.on("error", (err) => {
      if (timer) clearTimeout(timer);
      resolve({
        output: `Could not start Claude Code CLI. Please check your installation and try again.\n\nInstall: curl -fsSL https://claude.ai/install.sh | bash\n\nDetails: ${err.message}`,
        exitCode: 1,
        killed: false,
        sessionId: null,
        stats: null,
        errors: [],
      });
    });
  });

  return { process: proc, result };
}
