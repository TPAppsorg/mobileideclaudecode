import { createClient } from "@supabase/supabase-js";
import { getConfig } from "../src/config.js";
import { bridgeAuthFileStorage } from "../src/auth-storage.js";

async function run() {
  const config = getConfig({});
  console.log("Supabase URL:", config.supabaseUrl);
  
  const client = createClient(config.supabaseUrl, config.supabaseAnonKey, {
    auth: {
      storage: bridgeAuthFileStorage,
      persistSession: true,
      autoRefreshToken: true
    }
  });
  
  // Restore session
  const { data: { session } } = await client.auth.getSession();
  if (!session) {
    console.error("No persisted session found in storage!");
    return;
  }
  console.log("Authenticated as user ID:", session.user?.id);

  console.log("\n--- config.json values ---");
  console.log("Local Config Pair ID:", config.pairId);

  console.log("\n--- Recent device_pairs ---");
  const { data: pairs, error: pairsErr } = await client
    .from("device_pairs")
    .select("*")
    .limit(5);

  if (pairsErr) {
    console.error("Error fetching device_pairs:", pairsErr);
  } else {
    console.table(pairs);
  }

  console.log("\n--- Recent bridge_sessions ---");
  const { data: sessions, error: sessErr } = await client
    .from("bridge_sessions")
    .select("*")
    .limit(5);

  if (sessErr) {
    console.error("Error fetching bridge_sessions:", sessErr);
  } else {
    console.table(sessions);
  }

  console.log("\n--- Recent messages ---");
  const { data: messages, error: msgErr } = await client
    .from("messages")
    .select("*")
    .limit(5);

  if (msgErr) {
    console.error("Error fetching messages:", msgErr);
  } else {
    console.table(messages);
  }
}

run().catch(console.error);
