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
  
  const { data: pairs, error: pairsErr } = await client
    .from("device_pairs")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(10);

  if (pairsErr) {
    console.error("Error fetching device_pairs:", pairsErr);
  } else {
    console.log(JSON.stringify(pairs, null, 2));
  }
}

run().catch(console.error);
