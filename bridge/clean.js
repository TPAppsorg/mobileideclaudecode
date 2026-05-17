import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config({ path: '../supabase/.env' });

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

const client = createClient(supabaseUrl, supabaseKey);

async function main() {
  console.log("Cleaning up messages...");
  await client.from('messages').delete().neq('id', '00000000-0000-0000-0000-000000000000');
  
  console.log("Cleaning up bridge_sessions...");
  await client.from('bridge_sessions').delete().neq('id', '00000000-0000-0000-0000-000000000000');
  
  console.log("Cleaning up device_pairs...");
  await client.from('device_pairs').delete().neq('id', '00000000-0000-0000-0000-000000000000');

  console.log("Done!");
}

main();
