import { createClient, SupabaseClient, RealtimeChannel } from "@supabase/supabase-js";
import { BridgeConfig, saveConfig } from "./config.js";
import { bridgeAuthFileStorage, isBridgeAuthPersistenceDisabled } from "./auth-storage.js";
import path from "node:path";

// ─── Types ───────────────────────────────────────────────────────────

export interface MessageRow {
  id: string;
  created_at: string;
  role: string;
  content: string;
  status: string;
  session_id: string | null;
  model: string | null;
  user_id: string | null;
  client_type: string | null;
  pair_id: string | null;
  parent_message_id: string | null;
  is_cancelled: boolean;
  cancelled_at: string | null;
}

export interface BridgeSession {
  id: string;
  pair_id: string;
  is_active: boolean;
  project_name: string | null;
  project_path: string | null;
  client_type: string | null;
}

type BroadcastPayload = {
  new?: MessageRow;
  old?: MessageRow;
  type?: string;
};

// ─── Supabase Bridge Class ───────────────────────────────────────────

export class SupabaseBridge {
  public client: SupabaseClient;
  private channel: RealtimeChannel | null = null;
  private config: BridgeConfig;
  private _onMessage: ((msg: MessageRow) => void) | null = null;
  private _onCancel: ((messageId: string) => void) | null = null;
  private _onResetSession: (() => void) | null = null;
  private _pairId: string | null = null;
  private _sessionId: string | null = null;

  constructor(config: BridgeConfig) {
    this.config = config;
    this._pairId = config.pairId;

    const storageOptions = isBridgeAuthPersistenceDisabled()
      ? {}
      : { storage: bridgeAuthFileStorage, autoRefreshToken: true };

    this.client = createClient(config.supabaseUrl, config.supabaseAnonKey, {
      auth: {
        persistSession: !isBridgeAuthPersistenceDisabled(),
        ...storageOptions,
      },
    });
  }

  get pairId(): string | null { return this._pairId; }
  set pairId(val: string | null) { this._pairId = val; }
  get sessionId(): string | null { return this._sessionId; }

  // ── Auth ────────────────────────────────────────────────────────────

  async signInAnonymously(): Promise<string | null> {
    // First try restoring the persisted session
    const { data: { session } } = await this.client.auth.getSession();
    if (session?.user?.id) {
      return session.user.id;
    }

    // Sign in anonymously
    const { data, error } = await this.client.auth.signInAnonymously();
    if (error) {
      return null;
    }
    return data.user?.id ?? null;
  }

  // ── Pairing ─────────────────────────────────────────────────────────

  async claimPair(pairId: string, token: string): Promise<boolean> {
    const { data, error } = await this.client.rpc("claim_pair", {
      p_pair_id: pairId,
      p_pairing_token: token,
    });

    if (error) {
      return false;
    }

    this._pairId = pairId;
    saveConfig({ pairId });
    return true;
  }

  async isPairActive(pairId: string): Promise<boolean> {
    const { data, error } = await this.client
      .from("device_pairs")
      .select("is_active")
      .eq("id", pairId)
      .maybeSingle();
    if (error || !data) return false;
    return data.is_active === true;
  }

  // ── Bridge Session ──────────────────────────────────────────────────

  async upsertBridgeSession(): Promise<string | null> {
    if (!this._pairId) return null;

    const projectName = path.basename(this.config.projectPath || process.cwd());
    const projectPath = this.config.projectPath || process.cwd();

    // Deactivate existing sessions for this pair
    await this.client
      .from("bridge_sessions")
      .update({ is_active: false, ended_at: new Date().toISOString() })
      .eq("pair_id", this._pairId)
      .eq("is_active", true);

    // Create new session
    const { data, error } = await this.client
      .from("bridge_sessions")
      .insert({
        pair_id: this._pairId,
        is_active: true,
        project_name: projectName,
        project_path: projectPath,
        client_type: this.config.clientType,
      })
      .select("id")
      .single();

    if (error) {
      return null;
    }

    this._sessionId = data.id;
    return data.id;
  }

  // ── Channel ─────────────────────────────────────────────────────────

  async joinPairChannel(): Promise<void> {
    if (!this._pairId) return;

    if (this.channel) {
      await this.channel.unsubscribe();
    }

    const channelName = `pair:${this._pairId}`;

    this.channel = this.client
      .channel(channelName, { config: { private: true } })

      // Track presence
      .on("presence", { event: "join" }, ({ newPresences }) => {
        for (const p of newPresences) {
          if (p.role === "ios") {
            console.log("  📱 iOS device connected");
          }
        }
      })
      .on("presence", { event: "leave" }, ({ leftPresences }) => {
        for (const p of leftPresences) {
          if (p.role === "ios") {
            console.log("  📱 iOS device disconnected");
          }
        }
      })

      // Broadcast: message changes (from DB trigger)
      .on("broadcast", { event: "INSERT" }, ({ payload }: { payload: any }) => {
        const row = payload?.record || payload?.new;
        if (!row) return;
        // Only process user messages destined for this bridge
        if (row.role === "user" && row.status === "pending" && row.client_type === this.config.clientType) {
          console.log(`  📩 New message received`);
          this._onMessage?.(row);
        }
      })

      // Broadcast: cancel signal from iOS
      .on("broadcast", { event: "cancel" }, ({ payload }: { payload: { messageId?: string } }) => {
        if (payload?.messageId) {

          this._onCancel?.(payload.messageId);
        }
      })

      // Broadcast: reset session signal from iOS
      .on("broadcast", { event: "reset_session" }, () => {

        this._onResetSession?.();
      });

    // Subscribe
    const status = await this.channel.subscribe(async (status: string) => {
      if (status === "SUBSCRIBED") {
        // Track bridge presence
        await this.channel!.track({
          role: "bridge",
          project_name: path.basename(this.config.projectPath || process.cwd()),
          project_path: this.config.projectPath || process.cwd(),
          client_type: this.config.clientType,
        });
      }
    });
  }

  // ── Message CRUD ────────────────────────────────────────────────────

  async updateMessageStatus(messageId: string, status: string): Promise<void> {
    await this.client
      .from("messages")
      .update({ status, processed_by_mac_at: new Date().toISOString() })
      .eq("id", messageId);
  }

  async insertAgentReply(
    userMessageId: string,
    content: string,
    model: string | null,
  ): Promise<void> {
    const { data: userMsg } = await this.client
      .from("messages")
      .select("user_id, pair_id, client_type")
      .eq("id", userMessageId)
      .single();

    await this.client.from("messages").insert({
      role: "agent",
      content,
      status: "completed",
      user_id: userMsg?.user_id || null,
      pair_id: userMsg?.pair_id || this._pairId,
      parent_message_id: userMessageId,
      model: model || null,
      client_type: userMsg?.client_type || this.config.clientType,
    });
  }

  async isMessageCancelled(messageId: string): Promise<boolean> {
    const { data } = await this.client
      .from("messages")
      .select("is_cancelled")
      .eq("id", messageId)
      .single();
    return data?.is_cancelled === true;
  }

  // ── Broadcast chunk to iOS ──────────────────────────────────────────

  async broadcastChunk(parentMessageId: string, delta: string): Promise<void> {
    if (!this.channel) return;
    await this.channel.send({
      type: "broadcast",
      event: "chunk",
      payload: { messageId: parentMessageId, delta },
    });
  }

  // ── Event handlers ──────────────────────────────────────────────────

  onMessage(handler: (msg: MessageRow) => void): void { this._onMessage = handler; }
  onCancel(handler: (messageId: string) => void): void { this._onCancel = handler; }
  onResetSession(handler: () => void): void { this._onResetSession = handler; }

  // ── Cleanup ─────────────────────────────────────────────────────────

  async disconnect(): Promise<void> {
    if (this.channel) {
      await this.channel.unsubscribe();
      this.channel = null;
    }
    if (this._sessionId && this._pairId) {
      await this.client
        .from("bridge_sessions")
        .update({ is_active: false, ended_at: new Date().toISOString() })
        .eq("id", this._sessionId);
    }
  }
}
