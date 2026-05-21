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

describe("Claude Mobile Bridge Stress & Resilience Tests", () => {
  let bridgeProc: ChildProcess;
  let testBridge: SupabaseBridge;
  let testPairId: string;
  let testSessionId: string;
  let hasConfigBackup = false;

  beforeAll(async () => {
    testPairId = crypto.randomUUID();
    testSessionId = crypto.randomUUID();

    // Backup existing configuration
    hasConfigBackup = fs.existsSync(configFile);
    if (hasConfigBackup) fs.copyFileSync(configFile, configBackupFile);

    fs.mkdirSync(configDir, { recursive: true });

    // Write temp config.json
    fs.writeFileSync(
      configFile,
      JSON.stringify({ pairId: testPairId }, null, 2)
    );

    // Force auth persistence disabled for helper client setup
    process.env.BRIDGE_DISABLE_AUTH_PERSISTENCE = "true";

    const config = getConfig({ path: "./" });
    testBridge = new SupabaseBridge(config);
    const userId = await testBridge.signInAnonymously();
    expect(userId).toBeDefined();

    // Pre-insert device pair & active session
    await testBridge.client.from("device_pairs").insert({
      id: testPairId,
      ios_auth_user_id: userId,
      bridge_auth_user_id: userId,
      is_active: true
    });

    await testBridge.client.from("bridge_sessions").insert({
      id: testSessionId,
      pair_id: testPairId,
      is_active: true,
      client_type: "claudecodemobile",
      project_name: "claudemobile-bridge"
    });

    // Start bridge subprocess on port 39996
    const runEnv = { ...process.env };
    delete runEnv.BRIDGE_DISABLE_AUTH_PERSISTENCE;

    bridgeProc = spawn("npx", ["tsx", "src/index.ts", "--port", "39996"], {
      cwd: bridgeRootPath,
      env: {
        ...runEnv,
        CLAUDE_CLI_PATH: mockCliPath,
      }
    });

    // Wait for bridge to connect
    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("Bridge start timeout")), 15000);
      bridgeProc.stdout?.on("data", (data) => {
        const out = data.toString();
        if (out.includes("Connected!") || out.includes("Reconnected!")) {
          clearTimeout(timeout);
          resolve();
        }
      });
      bridgeProc.stderr?.on("data", (data) => {
        if (data.toString().includes("Error: ")) {
          clearTimeout(timeout);
          reject(new Error(`Bridge CLI error: ${data.toString()}`));
        }
      });
    });

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
        testSessionId = data.id;
        break;
      }
    }
  });

  afterAll(async () => {
    if (bridgeProc) bridgeProc.kill("SIGKILL");

    if (testPairId && testBridge) {
      await testBridge.client.from("messages").delete().eq("pair_id", testPairId);
      await testBridge.client.from("bridge_sessions").delete().eq("pair_id", testPairId);
      await testBridge.client.from("device_pairs").delete().eq("id", testPairId);
    }
    if (testBridge) await testBridge.disconnect();

    if (hasConfigBackup) {
      fs.copyFileSync(configBackupFile, configFile);
      fs.unlinkSync(configBackupFile);
    } else {
      try { fs.unlinkSync(configFile); } catch {}
    }
  });

  it("should handle long streaming response successfully", async () => {
    const userMessageId = crypto.randomUUID();
    const iosChannel = testBridge.client.channel(`pair:${testPairId}`, {
      config: { private: true, broadcast: { self: false, ack: false } }
    });

    const receivedChunks: string[] = [];

    await new Promise<void>((resolve) => {
      iosChannel
        .on("broadcast", { event: "chunk" }, (payload) => {
          if (payload?.payload?.messageId === userMessageId) {
            receivedChunks.push(payload.payload.delta);
          }
        })
        .subscribe((status) => {
          if (status === "SUBSCRIBED") resolve();
        });
    });

    // Create user message in DB targeting 'long-stream'
    await testBridge.client.from("messages").insert({
      id: userMessageId,
      role: "user",
      content: "long-stream",
      status: "pending",
      pair_id: testPairId,
      session_id: testSessionId,
      user_id: testBridge.client.auth.getUser() ? (await testBridge.client.auth.getUser()).data.user?.id : null,
      client_type: "claudecodemobile"
    });

    // Broadcast INSERT
    await iosChannel.send({
      type: "broadcast",
      event: "INSERT",
      payload: {
        record: {
          id: userMessageId,
          role: "user",
          content: "long-stream",
          status: "pending",
          session_id: testSessionId,
          client_type: "claudecodemobile"
        }
      }
    });

    // Wait for status to complete in DB
    let retries = 50;
    let replyFound = false;
    while (retries-- > 0 && !replyFound) {
      await new Promise((r) => setTimeout(r, 200));
      const { data } = await testBridge.client
        .from("messages")
        .select("*")
        .eq("parent_message_id", userMessageId)
        .eq("role", "agent")
        .maybeSingle();

      if (data && data.status === "completed") {
        replyFound = true;
      }
    }

    expect(replyFound).toBe(true);
    expect(receivedChunks.length).toBeGreaterThan(0); 
    expect(receivedChunks.join("")).toContain("chunk-0");
    expect(receivedChunks.join("")).toContain("chunk-99");

    await iosChannel.unsubscribe();
  }, 15000);

  it("should process user cancellation mid-execution and terminate subprocess", async () => {
    const userMessageId = crypto.randomUUID();
    const iosChannel = testBridge.client.channel(`pair:${testPairId}`, {
      config: { private: true, broadcast: { self: false, ack: false } }
    });

    await new Promise<void>((resolve) => {
      iosChannel.subscribe((status) => {
        if (status === "SUBSCRIBED") resolve();
      });
    });

    // Insert user message requesting 'sleep' (will sleep for 10s in mock-cli)
    await testBridge.client.from("messages").insert({
      id: userMessageId,
      role: "user",
      content: "sleep",
      status: "pending",
      pair_id: testPairId,
      session_id: testSessionId,
      user_id: testBridge.client.auth.getUser() ? (await testBridge.client.auth.getUser()).data.user?.id : null,
      client_type: "claudecodemobile"
    });

    // Broadcast INSERT to start execution
    await iosChannel.send({
      type: "broadcast",
      event: "INSERT",
      payload: {
        record: {
          id: userMessageId,
          role: "user",
          content: "sleep",
          status: "pending",
          session_id: testSessionId,
          client_type: "claudecodemobile"
        }
      }
    });

    // Wait briefly for the bridge to mark the message as 'processing'
    await new Promise((r) => setTimeout(r, 1000));

    // Update message to is_cancelled = true in the DB
    await testBridge.client
      .from("messages")
      .update({ is_cancelled: true })
      .eq("id", userMessageId);

    // Broadcast 'cancel' event to the bridge
    await iosChannel.send({
      type: "broadcast",
      event: "cancel",
      payload: { messageId: userMessageId }
    });

    // Wait for the user message to be marked as cancelled in the database
    let retries = 30;
    let cancelled = false;
    while (retries-- > 0 && !cancelled) {
      await new Promise((r) => setTimeout(r, 200));
      const { data } = await testBridge.client
        .from("messages")
        .select("status")
        .eq("id", userMessageId)
        .maybeSingle();

      if (data?.status === "cancelled") {
        cancelled = true;
      }
    }

    expect(cancelled).toBe(true);

    // Assert that no agent reply was created
    const { data: reply } = await testBridge.client
      .from("messages")
      .select("*")
      .eq("parent_message_id", userMessageId)
      .maybeSingle();

    expect(reply).toBeNull();

    await iosChannel.unsubscribe();
  }, 10000);

  it("should be resilient to iOS presence connection drops and reconnects mid-stream", async () => {
    const userMessageId = crypto.randomUUID();
    const iosChannel = testBridge.client.channel(`pair:${testPairId}`, {
      config: { private: true }
    });

    const receivedChunks: string[] = [];

    await new Promise<void>((resolve) => {
      iosChannel
        .on("broadcast", { event: "chunk" }, (payload) => {
          if (payload?.payload?.messageId === userMessageId) {
            receivedChunks.push(payload.payload.delta);
          }
        })
        .subscribe((status) => {
          if (status === "SUBSCRIBED") resolve();
        });
    });

    // Create user message
    await testBridge.client.from("messages").insert({
      id: userMessageId,
      role: "user",
      content: "long-stream",
      status: "pending",
      pair_id: testPairId,
      session_id: testSessionId,
      user_id: testBridge.client.auth.getUser() ? (await testBridge.client.auth.getUser()).data.user?.id : null,
      client_type: "claudecodemobile"
    });

    // Broadcast INSERT
    await iosChannel.send({
      type: "broadcast",
      event: "INSERT",
      payload: {
        record: {
          id: userMessageId,
          role: "user",
          content: "long-stream",
          status: "pending",
          session_id: testSessionId,
          client_type: "claudecodemobile"
        }
      }
    });

    // Wait 500ms to receive initial chunks, then simulate a sudden connection drop
    await new Promise((r) => setTimeout(r, 500));
    await iosChannel.unsubscribe();

    // Wait another 1000ms while bridge continues executing in background without active receiver
    await new Promise((r) => setTimeout(r, 1000));

    // Re-establish subscription/channel to simulate reconnect
    const reconnectChannel = testBridge.client.channel(`pair:${testPairId}`, {
      config: { private: true }
    });

    await new Promise<void>((resolve) => {
      reconnectChannel
        .on("broadcast", { event: "chunk" }, (payload) => {
          if (payload?.payload?.messageId === userMessageId) {
            receivedChunks.push(payload.payload.delta);
          }
        })
        .subscribe((status) => {
          if (status === "SUBSCRIBED") resolve();
        });
    });

    // Wait for bridge execution to complete
    let retries = 30;
    let replyFound = false;
    while (retries-- > 0 && !replyFound) {
      await new Promise((r) => setTimeout(r, 200));
      const { data } = await testBridge.client
        .from("messages")
        .select("*")
        .eq("parent_message_id", userMessageId)
        .eq("role", "agent")
        .maybeSingle();

      if (data && data.status === "completed") {
        replyFound = true;
      }
    }

    expect(replyFound).toBe(true);
    expect(receivedChunks.length).toBeGreaterThan(0);

    await reconnectChannel.unsubscribe();
  }, 10000);
});
