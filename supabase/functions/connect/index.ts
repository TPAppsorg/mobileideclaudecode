import "jsr:@supabase/functions-js/edge-runtime.d.ts";

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const token = url.searchParams.get("token");

  if (!token) {
    return new Response(
      `<!DOCTYPE html>
<html><head><title>Error</title>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<style>body{font-family:-apple-system,system-ui,sans-serif;background:#000;color:#fff;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
.container{text-align:center}h1{font-size:24px}p{color:#71717a;font-size:15px}</style>
</head><body><div class="container"><h1>Missing token</h1><p>Please use the link from the app.</p></div></body></html>`,
      {
        status: 400,
        headers: { "Content-Type": "text/html; charset=utf-8" },
      }
    );
  }

  // Redirect to local bridge pairing server
  const redirectUrl = `http://127.0.0.1:38476/callback?token=${encodeURIComponent(token)}`;

  return new Response(null, {
    status: 302,
    headers: { Location: redirectUrl },
  });
});
