import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { spawn, ChildProcess } from "node:child_process";
import fs from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { SupabaseBridge } from "../src/supabase.js";
import { getConfig } from "../src/config.js";
import crypto from "node:crypto";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const mockCliPath = path.join(__dirname, "mock-cli.js");
const bridgeRootPath = path.resolve(__dirname, "..");

const configDir = path.join(homedir(), ".claudecodemobile-bridge");
const configFile = path.join(configDir, "config.json");
const configBackupFile = path.join(configDir, "config.json.bak");

describe("Claude Mobile Bridge E2E Flow", () => {
  let bridgeProc: ChildProcess;
  let testBridge: SupabaseBridge;
  let testPairId: string;
  let testSessionId: string;
  let userMessageId: string;
  let hasConfigBackup = false;

  beforeAll(async () => {
    testPairId = crypto.randomUUID();
    testSessionId = crypto.randomUUID();
    userMessageId = crypto.randomUUID();

    // Backup existing configuration
    hasConfigBackup = fs.existsSync(configFile);
    if (hasConfigBackup) {
      fs.copyFileSync(configFile, configBackupFile);
    }

    fs.mkdirSync(configDir, { recursive: true });

    // Write temp config.json
    fs.writeFileSync(
      configFile,
      JSON.stringify(
        {
          pairId: testPairId,
        },
        null,
        2
      )
    );

    // Force auth persistence disabled for helper client setup
    process.env.BRIDGE_DISABLE_AUTH_PERSISTENCE = "true";

    const config = getConfig({ path: "./" });
    testBridge = new SupabaseBridge(config);
    const userId = await testBridge.signInAnonymously();
    expect(userId).toBeDefined();

    // Pre-insert device pair & session
    const { error: pairErr } = await testBridge.client.from("device_pairs").insert({
      id: testPairId,
      ios_auth_user_id: userId,
      bridge_auth_user_id: userId,
      is_active: true
    });
    if (pairErr) throw pairErr;

    const { error: sessionErr } = await testBridge.client.from("bridge_sessions").insert({
      id: testSessionId,
      pair_id: testPairId,
      is_active: true,
      client_type: "claudecodemobile",
      project_name: "claudemobile-bridge"
    });
    if (sessionErr) throw sessionErr;
  });

  afterAll(async () => {
    if (bridgeProc) {
      bridgeProc.kill("SIGKILL");
    }

    if (testPairId && testBridge) {
      await testBridge.client.from("messages").delete().eq("pair_id", testPairId);
      await testBridge.client.from("bridge_sessions").delete().eq("pair_id", testPairId);
      await testBridge.client.from("device_pairs").delete().eq("id", testPairId);
    }

    if (testBridge) {
      await testBridge.disconnect();
    }

    // Restore backups
    if (hasConfigBackup) {
      fs.copyFileSync(configBackupFile, configFile);
      fs.unlinkSync(configBackupFile);
    } else {
      try { fs.unlinkSync(configFile); } catch {}
    }
  });

  it("should start the bridge CLI, process broadcast user message, stream chunks, and save reply", async () => {
    // Start bridge subprocess on port 39995
    const runEnv = { ...process.env };
    delete runEnv.BRIDGE_DISABLE_AUTH_PERSISTENCE;

    bridgeProc = spawn("npx", ["tsx", "src/index.ts", "--port", "39995"], {
      cwd: bridgeRootPath,
      env: {
        ...runEnv,
        CLAUDE_CLI_PATH: mockCliPath,
      }
    });

    // Wait for bridge to connect and become active
    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error("Bridge start timeout - did not output connected message in time"));
      }, 15000);

      bridgeProc.stdout?.on("data", (data) => {
        const out = data.toString();
        console.log("[E2E Claude Stdout]:", out);
        if (out.includes("Connected!") || out.includes("Reconnected!")) {
          clearTimeout(timeout);
          resolve();
        }
      });

      bridgeProc.stderr?.on("data", (data) => {
        const err = data.toString();
        console.error("[E2E Claude Stderr]:", err);
        if (err.includes("Error: ")) {
          clearTimeout(timeout);
          reject(new Error(`Bridge CLI error: ${err}`));
        }
      });
    });

    // Connect mock iOS client to channel
    const iosChannel = testBridge.client.channel(`pair:${testPairId}`, {
      config: {
        private: true,
      }
    });

    const receivedChunks: string[] = [];

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error("Timeout waiting for channel subscription"));
      }, 5000);

      iosChannel
        .on("broadcast", { event: "chunk" }, (payload) => {
          if (payload?.payload?.messageId === userMessageId) {
            receivedChunks.push(payload.payload.delta);
          }
        })
        .subscribe((status, err) => {
          if (status === "SUBSCRIBED") {
            clearTimeout(timeout);
            resolve();
          } else if (err) {
            clearTimeout(timeout);
            reject(err);
          }
        });
    });

    // Wait for the bridge to create its session and go online
    let activeSessionId = testSessionId;
    let sessionRetries = 30;
    while (sessionRetries-- > 0) {
      await new Promise(r => setTimeout(r, 200));
      const { data } = await testBridge.client
        .from("bridge_sessions")
        .select("id")
        .eq("pair_id", testPairId)
        .eq("is_active", true)
        .maybeSingle();
      if (data?.id) {
        activeSessionId = data.id;
        break;
      }
    }

    // Create user message in DB
    const { error: msgErr } = await testBridge.client.from("messages").insert({
      id: userMessageId,
      role: "user",
      content: "stream",
      status: "pending",
      pair_id: testPairId,
      session_id: activeSessionId,
      user_id: testBridge.client.auth.getUser() ? (await testBridge.client.auth.getUser()).data.user?.id : null,
      client_type: "claudecodemobile"
    });
    expect(msgErr).toBeNull();

    // Broadcast INSERT event
    await iosChannel.send({
      type: "broadcast",
      event: "INSERT",
      payload: {
        record: {
          id: userMessageId,
          role: "user",
          content: "stream",
          status: "pending",
          session_id: activeSessionId,
          client_type: "claudecodemobile"
        }
      }
    });

    // Wait for chunks to stream and database reply row to be inserted
    let retries = 30;
    let replyFound = false;
    let finalReplyContent = "";

    while (retries-- > 0 && !replyFound) {
      await new Promise((r) => setTimeout(r, 500));

      const { data } = await testBridge.client
        .from("messages")
        .select("*")
        .eq("parent_message_id", userMessageId)
        .eq("role", "agent")
        .maybeSingle();

      if (data && data.status === "completed") {
        replyFound = true;
        finalReplyContent = data.content;
      }
    }

    expect(replyFound).toBe(true);
    expect(finalReplyContent).toContain("This is a streamed mock response.");

    // Verify broadcast chunks were received by our client
    expect(receivedChunks.length).toBeGreaterThanOrEqual(1);
    expect(receivedChunks.join("")).toContain("This is a streamed mock response.");
  }, 30000);
});
