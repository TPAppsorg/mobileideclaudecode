import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config({ path: './supabase/.env' });

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_ANON_KEY;

const client = createClient(supabaseUrl, supabaseKey);

async function main() {
  const { data: pairs } = await client.from('device_pairs').select('*').order('created_at', { ascending: false }).limit(5);
  console.log("Latest device_pairs:", pairs);
  
  const { data: sessions } = await client.from('bridge_sessions').select('*').order('started_at', { ascending: false }).limit(5);
  console.log("Latest bridge_sessions:", sessions);
}

main();
