import { createClient } from "@supabase/supabase-js";
import dotenv from "dotenv";
import { getConfig } from "../src/config.js";

dotenv.config({ path: "../supabase/.env" });

async function run() {
  const config = getConfig({});
  const supabaseUrl = process.env.SUPABASE_URL || config.supabaseUrl;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!serviceRoleKey) {
    console.error("SUPABASE_SERVICE_ROLE_KEY not found in env!");
    return;
  }

  const client = createClient(supabaseUrl, serviceRoleKey);

  console.log("Checking top 3 device_pairs (Admin View):");
  const { data: pairs, error: pairsErr } = await client
    .from("device_pairs")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(3);

  if (pairsErr) {
    console.error("Error fetching device_pairs:", pairsErr);
  } else {
    console.log(JSON.stringify(pairs, null, 2));
  }
}

run().catch(console.error);
