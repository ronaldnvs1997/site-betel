import { createClient } from "npm:@supabase/supabase-js@2";
import { criarHandler } from "./handler.ts";
Deno.serve(criarHandler({ createClient, env: (k) => Deno.env.get(k) }));
