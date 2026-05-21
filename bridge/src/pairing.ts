import http from "node:http";
import { URL } from "node:url";

export interface PairingCallbackData {
  pairId: string;
  token: string;
}

/**
 * Simple HTTP server that listens on 127.0.0.1:<port>.
 * When the browser opens the connect URL, Supabase edge function redirects here
 * with ?token=<pairing_token> — this callback triggers pairing.
 */
export function startPairingServer(
  port: number,
  onPairCallback: (data: PairingCallbackData) => Promise<void>,
): http.Server {
  const server = http.createServer(async (req, res) => {
    // Set CORS headers globally
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With");

    if (req.method === "OPTIONS") {
      res.writeHead(204);
      res.end();
      return;
    }

    const url = new URL(req.url || "/", `http://127.0.0.1:${port}`);

    if (url.pathname === "/callback") {
      const token = url.searchParams.get("token");
      const pairId = url.searchParams.get("pair");

      if (!token) {
        res.writeHead(400, { "Content-Type": "text/html" });
        res.end("<html><body><h1>❌ Missing token</h1><p>Please use the link from the app.</p></body></html>");
        return;
      }

      try {
        await onPairCallback({ pairId: pairId || "", token });
        res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
        res.end(`<!DOCTYPE html>
<html><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<style>body{font-family:-apple-system,system-ui,sans-serif;background:#0a0a0a;color:#fff;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;flex-direction:column}
.emoji{font-size:64px;margin-bottom:16px}.title{font-size:24px;font-weight:700;margin-bottom:8px}.sub{color:#71717a;font-size:15px}</style>
</head><body>
<div class="emoji">✅</div>
<div class="title">Connected!</div>
<div class="sub">Claude Code Mobile is now connected. You can close this tab.</div>
</body></html>`);
      } catch (err) {
        res.writeHead(500, { "Content-Type": "text/html; charset=utf-8" });
        res.end(`<!DOCTYPE html>
<html><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<style>body{font-family:-apple-system,system-ui,sans-serif;background:#0a0a0a;color:#fff;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;flex-direction:column}
.emoji{font-size:64px;margin-bottom:16px}.title{font-size:24px;font-weight:700;margin-bottom:8px;color:#ef4444}.sub{color:#71717a;font-size:15px}</style>
</head><body>
<div class="emoji">❌</div>
<div class="title">Connection Failed</div>
<div class="sub">${(err as Error)?.message || "Unknown error"}</div>
</body></html>`);
      }
      return;
    }

    // Health check
    if (url.pathname === "/health") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ status: "ok", bridge: "claudecodemobile" }));
      return;
    }

    res.writeHead(404, { "Content-Type": "text/plain" });
    res.end("Not Found");
  });

  server.listen(port, "127.0.0.1", () => {

  });

  return server;
}
