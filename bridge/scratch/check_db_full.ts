import { createClient } from "@supabase/supabase-js";
import { getConfig } from "../src/config.js";
import { bridgeAuthFileStorage } from "../src/auth-storage.js";

async function run() {
  const config = getConfig({});
  const client = createClient(config.supabaseUrl, config.supabaseAnonKey, {
    auth: {
      storage: bridgeAuthFileStorage,
      persistSession: true,
      autoRefreshToken: true
    }
  });
  
  const { data: { session } } = await client.auth.getSession();
  if (!session) {
    console.error("No persisted session found!");
    return;
  }
  console.log("Authenticated User ID:", session.user?.id);
  console.log("Local config pairId:", config.pairId);

  // 1. Fetch the local config's pair details
  if (config.pairId) {
    console.log(`\nChecking configured pairId ${config.pairId}:`);
    const { data: pair, error } = await client
      .from("device_pairs")
      .select("*")
      .eq("id", config.pairId)
      .maybeSingle();
    
    if (error) console.error("Error fetching configured pair:", error);
    else console.log(JSON.stringify(pair, null, 2));
  }

  // 2. Fetch recent active pairs
  console.log("\n--- Active/Recent device_pairs ---");
  const { data: pairs, error: pairsErr } = await client
    .from("device_pairs")
    .select("*")
    .order("is_active", { ascending: false });

  if (pairsErr) {
    console.error("Error fetching device_pairs:", pairsErr);
  } else {
    for (const pair of pairs || []) {
      console.log(`Pair ID: ${pair.id}`);
      console.log(`  is_active: ${pair.is_active}`);
      console.log(`  pairing_token: ${pair.pairing_token}`);
      console.log(`  bridge_auth_user_id: ${pair.bridge_auth_user_id}`);
      console.log(`  ios_auth_user_id: ${pair.ios_auth_user_id}`);
      console.log(`  created_at: ${pair.created_at || pair.inserted_at}`);
    }
  }

  // 3. Fetch recent bridge sessions
  console.log("\n--- Active bridge_sessions ---");
  const { data: sessions, error: sessErr } = await client
    .from("bridge_sessions")
    .select("*")
    .eq("is_active", true);

  if (sessErr) {
    console.error("Error fetching bridge_sessions:", sessErr);
  } else {
    console.log(JSON.stringify(sessions, null, 2));
  }

  // 4. Fetch recent messages
  console.log("\n--- Last 3 Messages ---");
  const { data: messages, error: msgErr } = await client
    .from("messages")
    .select("id, role, status, pair_id, content")
    .order("id", { ascending: false }) // Or timestamp
    .limit(3);

  if (msgErr) {
    console.error("Error fetching messages:", msgErr);
  } else {
    console.log(JSON.stringify(messages, null, 2));
  }
}

run().catch(console.error);
