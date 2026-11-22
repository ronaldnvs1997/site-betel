// Servidor local só para testar o site no computador (o Render publica a pasta site/ como site estático).
// Uso: npm run dev   → gera site/config.js a partir do .env e abre em http://localhost:8080
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
const SITE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../site");
const PORTA = Number(process.env.PORT || 8080);
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".jpg": "image/jpeg",
  ".png": "image/png", ".webp": "image/webp", ".svg": "image/svg+xml", ".mp4": "video/mp4", ".mp3": "audio/mpeg", ".ico": "image/x-icon", ".json": "application/json" };
// mesmos cabeçalhos do render.yaml
const BASE = { "X-Content-Type-Options": "nosniff", "X-Frame-Options": "SAMEORIGIN", "Referrer-Policy": "strict-origin-when-cross-origin", "Permissions-Policy": "camera=(), microphone=(), geolocation=()" };
http.createServer((req, res) => {
  const u = new URL(req.url, "http://localhost");
  let p = decodeURIComponent(u.pathname);
  if (p === "/agendaministerialprivada/evento") p += "/";           // mesma regra de reescrita do render.yaml
  let f = path.join(SITE, p.endsWith("/") ? p + "index.html" : p);
  if (!f.startsWith(SITE) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404, BASE); return res.end("Página não encontrada"); }
  const extra = p.startsWith("/agendaministerialprivada/") ? { "X-Robots-Tag": "noindex, nofollow", "Referrer-Policy": "no-referrer", "Cache-Control": "no-store" } : {};
  res.writeHead(200, { "Content-Type": MIME[path.extname(f)] || "application/octet-stream", ...BASE, ...extra });
  fs.createReadStream(f).pipe(res);
}).listen(PORTA, () => console.log(`Site em http://localhost:${PORTA}`));
