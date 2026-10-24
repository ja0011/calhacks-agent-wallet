// Loads server/.env regardless of the directory the process is launched from.
// Import this first in entry points so env vars exist before other modules read them.
import { fileURLToPath } from "node:url";
import dotenv from "dotenv";

dotenv.config({
  path: fileURLToPath(new URL("../.env", import.meta.url)),
  quiet: true,
});
console.log(`[startup] ${new Date().toISOString()} env loaded`);
