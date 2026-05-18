import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config({ path: '../supabase/.env' });

const client = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function main() {
  const { data } = await client.from('messages').select('id, content, status, is_cancelled').order('created_at', { ascending: false }).limit(5);
  console.log("Latest messages:");
  console.table(data);
}
main();
