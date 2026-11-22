// Monta a VERSÃO DE TESTE (roda no navegador): site + núcleo + banco em WebAssembly.
// Uso: node ferramentas/construir-previa.mjs <pasta-do-site> <saida>
import { lerEtapas } from "../nucleo/etapas.mjs";
import { build } from "esbuild";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const RAIZ = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const SITE = path.resolve(process.argv[2] || path.join(RAIZ, "site"));
const SAIDA = path.resolve(process.argv[3] || path.join(RAIZ, "previa/dist"));

// etapas do banco (as mesmas do servidor) + exemplos da Agenda para a demonstração
const etapas = lerEtapas(RAIZ, [{ nome: "002_exemplos_agenda", sql: fs.readFileSync(path.join(RAIZ, "previa/exemplos-agenda.sql"), "utf8") }]);
const SEGREDO = "previa-betel-" + crypto.randomBytes(24).toString("hex");
// Contas da demonstração: PREVIA_CONTAS="Nome|email|telefone;Nome|email|telefone" (senha temporária: PREVIA_SENHA)
const SENHA_PREVIA = process.env.PREVIA_SENHA || "Betel-Teste-2026";
const CONTAS = (process.env.PREVIA_CONTAS || "Administrador de Teste|admin@exemplo.com|31900000000").split(";").map((x) => x.trim()).filter(Boolean)
  .map((x) => { const [nome, email, telefone] = x.split("|").map((y) => (y || "").trim()); return { nome, email: email.toLowerCase(), telefone: (telefone || "").replace(/\D/g, ""), senha: SENHA_PREVIA }; });
fs.writeFileSync(path.join(RAIZ, "previa/etapas.gerado.mjs"), `export const ETAPAS = ${JSON.stringify(etapas)};\nexport const SEGREDO = ${JSON.stringify(SEGREDO)};\nexport const CONTAS = ${JSON.stringify(CONTAS)};\nexport const PASTA = "./";\n`);

fs.rmSync(SAIDA, { recursive: true, force: true });
fs.cpSync(SITE, SAIDA, { recursive: true, filter: (f) => !/config\.js$/.test(f) });
await build({ entryPoints: [path.join(RAIZ, "previa/entrada.mjs")], bundle: true, format: "iife", platform: "browser", target: "es2022",
  outfile: path.join(SAIDA, "betel-previa.js"), minify: true, legalComments: "none", define: { "import.meta.url": "undefined" }, external: ["node:*"], logLevel: "error" });
const PG = path.join(RAIZ, "node_modules/@electric-sql/pglite/dist");
for (const f of ["pglite.wasm", "initdb.wasm"]) fs.copyFileSync(path.join(PG, f), path.join(SAIDA, f));
fs.writeFileSync(path.join(SAIDA, "pglite-data.txt"), fs.readFileSync(path.join(PG, "pglite.data")).toString("base64"));

// chave pública da versão de teste (mesmo formato do servidor)
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
const h = b64({ alg: "HS256", typ: "JWT" }), p = b64({ role: "anon", iss: "betel" });
const ANON = `${h}.${p}.${crypto.createHmac("sha256", SEGREDO).update(h + "." + p).digest("base64url")}`;
fs.writeFileSync(path.join(SAIDA, "config.js"), `// Versão de teste: a API roda neste navegador (betel-previa.js)
window.BETEL_SUPABASE = { url: location.origin + "/__betel", anonKey: ${JSON.stringify(ANON)}, recuperacaoPorEmail: true };
(function () { var s = document.currentScript && document.currentScript.src || location.href; document.write('<script src="' + new URL("betel-previa.js", s).href + '"><\\/script>'); })();
`);
const tam = (f) => (fs.statSync(path.join(SAIDA, f)).size / 1048576).toFixed(1) + " MB";
console.log("Versão de teste montada em", SAIDA, "— betel-previa.js", tam("betel-previa.js"), "· pglite.wasm", tam("pglite.wasm"), "· pglite-data.txt", tam("pglite-data.txt"));
