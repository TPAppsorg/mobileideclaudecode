import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { SupabaseBridge } from "../src/supabase.js";
import { getConfig } from "../src/config.js";
import crypto from "node:crypto";

describe("SupabaseBridge integration", () => {
  let bridge: SupabaseBridge;
  let testPairId: string;
  let testSessionId: string | null = null;
  let parentMessageId: string;
  let userId: string | null = null;

  beforeAll(async () => {
    // Disable auth file storage persistence to avoid polluting developer config
    process.env.BRIDGE_DISABLE_AUTH_PERSISTENCE = "true";

    const config = getConfig({ path: "./" });
    bridge = new SupabaseBridge(config);

    // 1. Sign in anonymously
    userId = await bridge.signInAnonymously();
    expect(userId).toBeDefined();
    expect(userId).not.toBeNull();

    // 2. Generate randomized sandboxed IDs
    testPairId = crypto.randomUUID();
    parentMessageId = crypto.randomUUID();

    // 3. Insert mock pair row directly through client
    const { error: insertErr } = await bridge.client.from("device_pairs").insert({
      id: testPairId,
      ios_auth_user_id: userId,
      bridge_auth_user_id: userId,
      is_active: true,
      pairing_token: "test-pairing-token"
    });
    
    if (insertErr) {
      throw new Error(`Failed to insert test pair: ${insertErr.message}`);
    }
  });

  afterAll(async () => {
    // 4. Teardown of all sandboxed data
    if (testPairId) {
      await bridge.client.from("messages").delete().eq("pair_id", testPairId);
      await bridge.client.from("bridge_sessions").delete().eq("pair_id", testPairId);
      await bridge.client.from("device_pairs").delete().eq("id", testPairId);
    }
    await bridge.disconnect();
  });

  it("should verify active pair", async () => {
    const active = await bridge.isPairActive(testPairId);
    expect(active).toBe(true);
  });

  it("should claim pair with a valid pairing token", async () => {
    const claimed = await bridge.claimPair(testPairId, "test-pairing-token");
    expect(claimed).toBe(true);
    expect(bridge.pairId).toBe(testPairId);
  });

  it("should upsert bridge session", async () => {
    testSessionId = await bridge.upsertBridgeSession();
    expect(testSessionId).toBeDefined();
    expect(testSessionId).not.toBeNull();
    expect(bridge.sessionId).toBe(testSessionId);
  });

  it("should send and read messages under the sandboxed pair", async () => {
    // Insert mock parent user message first
    const { error: insertMsgErr } = await bridge.client.from("messages").insert({
      id: parentMessageId,
      role: "user",
      content: "Hello, this is a test prompt for Claude",
      status: "pending",
      pair_id: testPairId,
      session_id: testSessionId,
      user_id: userId,
      client_type: "claudecodemobile"
    });

    expect(insertMsgErr).toBeNull();

    // Send mock agent reply
    await bridge.insertAgentReply(
      parentMessageId,
      "Hello back from Claude mock!",
      "claude-mock-model"
    );

    // Verify reply was successfully written
    const { data: messages, error: readErr } = await bridge.client
      .from("messages")
      .select("*")
      .eq("parent_message_id", parentMessageId);

    expect(readErr).toBeNull();
    expect(messages?.length).toBe(1);
    expect(messages?.[0]?.content).toBe("Hello back from Claude mock!");
    expect(messages?.[0]?.status).toBe("completed");
  });
});
