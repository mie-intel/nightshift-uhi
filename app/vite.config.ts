import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

// deployments/testnet.json lives one level up (single source of addresses).
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: { fs: { allow: [".."] } },
  build: { target: "es2022", sourcemap: false },
});
