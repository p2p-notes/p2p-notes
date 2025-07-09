import wasm from "vite-plugin-wasm";
import gleam from "vite-gleam";
import toplevelawait from "vite-plugin-top-level-await";
import { defineConfig } from "vite";
export default defineConfig({
  plugins: [gleam(), wasm(), toplevelawait()],
});
