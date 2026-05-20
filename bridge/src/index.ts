#!/usr/bin/env node
import { Command } from "commander";
import path from "node:path";
import { ChildProcess } from "child_process";
import { getConfig, saveConfig } from "./config.js";
import { SupabaseBridge, MessageRow } from "./supabase.js";
import { findClaudeCLI, runClaude, terminateClaudeProcess } from "./claude.js";
import { startPairingServer } from "./pairing.js";
import { acquireSleepLock, releaseSleepLock } from "./sleep-lock.js";

// ─── CLI ─────────────────────────────────────────────────────────────

const program = new Command();
program
  .name("claudecodemobile-bridge")
  .description("Bridge between Claude Code CLI and Claude Code Mobile iOS app")
  .option("-p, --path <path>", "Project working directory", process.cwd())
  .option("--port <number>", "Pairing server port", "38476")
  .parse(process.argv);

const opts = program.opts<{ path: string; port: string }>();
const config = getConfig({ path: opts.path, port: parseInt(opts.port, 10) });

// ─── Globals ─────────────────────────────────────────────────────────

let bridge: SupabaseBridge;
let cliPath: string;
let currentProc: ChildProcess | null = null;
let currentMessageId: string | null = null;
let isFirstMessage = true;
const messageQueue: MessageRow[] = [];
let isProcessing = false;

// ─── Message Processing ─────────────────────────────────────────────

async function processMessage(msg: MessageRow): Promise<void> {
  currentMessageId = msg.id;
  console.log(`\n  ⚡ Processing message...`);

  // Mark as processing
  await bridge.updateMessageStatus(msg.id, "processing");

  // Check if cancelled before even starting
  const cancelled = await bridge.isMessageCancelled(msg.id);
  if (cancelled) {
    console.log("  Message cancelled before processing.");
    await bridge.updateMessageStatus(msg.id, "cancelled");
    currentMessageId = null;
    return;
  }

  let chunkBuffer = "";
  let chunkFlushTimer: ReturnType<typeof setInterval> | null = null;

  // Flush buffered chunks to iOS every 100ms
  const startChunkFlush = () => {
    chunkFlushTimer = setInterval(async () => {
      if (chunkBuffer) {
        const delta = chunkBuffer;
        chunkBuffer = "";
        await bridge.broadcastChunk(msg.id, delta);
      }
    }, 100);
  };

  const stopChunkFlush = async () => {
    if (chunkFlushTimer) {
      clearInterval(chunkFlushTimer);
      chunkFlushTimer = null;
    }
    // Flush remaining
    if (chunkBuffer) {
      await bridge.broadcastChunk(msg.id, chunkBuffer);
      chunkBuffer = "";
    }
  };

  startChunkFlush();

  // Start cancel polling
  let cancelPolling: ReturnType<typeof setInterval> | null = null;
  cancelPolling = setInterval(async () => {
    try {
      const isCancelled = await bridge.isMessageCancelled(msg.id);
      if (isCancelled && currentProc) {
        console.log("  🛑 Cancel detected — killing process");
        terminateClaudeProcess(currentProc);
      }
    } catch { /* ignore */ }
  }, 1000);

  try {
    const { process: proc, result } = runClaude(msg.content, cliPath, {
      cwd: config.projectPath || process.cwd(),
      model: msg.model || undefined,
      continueSession: !isFirstMessage,
      onChunk: (delta) => {
        chunkBuffer += delta;
      },
    });

    currentProc = proc;

    const res = await result;
    currentProc = null;

    await stopChunkFlush();
    if (cancelPolling) clearInterval(cancelPolling);

    // Check if cancelled during execution
    const wasCancelled = await bridge.isMessageCancelled(msg.id);
    if (wasCancelled || res.killed) {
      console.log("  Message was cancelled.");
      await bridge.updateMessageStatus(msg.id, "cancelled");
    } else {
      // Insert agent reply
      await bridge.insertAgentReply(msg.id, res.output, msg.model);
      // Mark user message as completed
      await bridge.updateMessageStatus(msg.id, "completed");
      console.log(`  ✅ Reply sent (${res.output.length} chars)`);
    }

    // After first successful message, subsequent ones use --continue
    isFirstMessage = false;

  } catch (err) {
    await stopChunkFlush();
    if (cancelPolling) clearInterval(cancelPolling);
    console.error("  ❌ Error:", (err as Error).message || err);
    await bridge.insertAgentReply(
      msg.id,
      `Error: ${(err as Error).message || "Unknown error"}`,
      null,
    );
  }

  currentMessageId = null;
}

async function processQueue(): Promise<void> {
  if (isProcessing) return;
  isProcessing = true;

  while (messageQueue.length > 0) {
    const msg = messageQueue.shift()!;
    await processMessage(msg);
  }

  isProcessing = false;
}

// ─── Main ────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  const dir = config.projectPath || process.cwd();
  const workspaceName = path.basename(dir);

  console.log("");
  console.log("  ┌───────────────────────────────────────┐");
  console.log("  │  Claude Code Mobile Bridge  v1.0       │");
  console.log("  └───────────────────────────────────────┘");
  console.log("");
  console.log(`  📂 Directory  ${dir}`);
  console.log("");

  // 1. Find Claude CLI
  cliPath = findClaudeCLI() || "";
  if (!cliPath) {
    console.error("");
    console.error("  ❌ Claude Code CLI not found.");
    if (process.platform === "win32") {
      console.error("     Install: npm install -g @anthropic-ai/claude-code");
    } else {
      console.error("     Install: curl -fsSL https://claude.ai/install.sh | bash");
    }
    console.error("");
    process.exit(1);
  }

  // 2. Initialize Supabase bridge
  bridge = new SupabaseBridge(config);
  const userId = await bridge.signInAnonymously();
  if (!userId) {
    console.error("  ❌ Failed to authenticate. Please try again.");
    process.exit(1);
  }

  // 3. Start pairing server
  const pairingServer = startPairingServer(config.port, async ({ pairId, token }) => {
    // Allow re-pairing: disconnect old pair and accept the new one
    if (bridge.pairId) {
      console.log("  🔄 New device connecting — switching pair...");
      await bridge.disconnect();
      isFirstMessage = true;
    }

    let resolvedPairId = pairId;

    if (!resolvedPairId) {
      const { data } = await bridge.client
        .from("device_pairs")
        .select("id")
        .eq("pairing_token", token)
        .single();
      if (data) resolvedPairId = data.id;
    }

    if (!resolvedPairId) {
      throw new Error("Could not resolve pair_id from callback");
    }

    const ok = await bridge.claimPair(resolvedPairId, token);
    if (!ok) throw new Error("Failed to claim pair");

    await bridge.upsertBridgeSession();
    await bridge.joinPairChannel();

    console.log("");
    console.log("  ✅ Connected!");
    console.log(`  📂 Workspace  ${workspaceName}`);
    console.log("");
    console.log("  Press Ctrl+C to stop the bridge.");
    console.log("");
  });

  // 4. If already paired (from saved config), reconnect
  if (config.pairId) {
    const active = await bridge.isPairActive(config.pairId);
    if (!active) {
      console.log("  Saved pairing is no longer active. Let's reconnect.");
      const { saveConfig } = await import("./config.js");
      saveConfig({ pairId: undefined });
      config.pairId = null;
      bridge.pairId = null;
    } else {
      await bridge.upsertBridgeSession();
      await bridge.joinPairChannel();
      console.log("  ✅ Reconnected!");
      console.log(`  📂 Workspace  ${workspaceName}`);
      console.log("");
      console.log("  Press Ctrl+C to stop the bridge.");
      console.log("");
    }
  }

  if (!config.pairId) {
    console.log("  ⏳ Waiting for connection from the iOS app...");
    console.log("     Open Claude Code Mobile on your iPhone — it will connect automatically.");
    console.log("");
  }

  // 5. Set up event handlers
  bridge.onMessage((msg) => {
    messageQueue.push(msg);
    processQueue();
  });

  bridge.onCancel((messageId) => {
    if (currentMessageId === messageId && currentProc) {
      console.log("  🛑 Cancel received — killing process");
      terminateClaudeProcess(currentProc);
    }
  });

  bridge.onResetSession(() => {
    isFirstMessage = true;
    console.log("  🔄 Session reset — next message will start fresh.");
  });

  // 6. Keep-alive: prevent system sleep
  acquireSleepLock();

  // 7. Graceful shutdown
  const shutdown = async () => {
    console.log("\n  Shutting down...");
    releaseSleepLock();
    if (currentProc) terminateClaudeProcess(currentProc);
    await bridge.disconnect();
    pairingServer.close();
    process.exit(0);
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

main().catch((err) => {
  console.error("  ❌ Fatal error:", err);
  process.exit(1);
});
