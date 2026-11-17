import { build } from "esbuild";
import { mkdir, readFile, writeFile, cp, readdir, rm } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const out = resolve(root, "build/LocalWeb");
await rm(out, { recursive: true, force: true });
await mkdir(out, { recursive: true });
await build({
  absWorkingDir: root,
  entryPoints: ["Web/entry.tsx"],
  outfile: `${out}/app.js`,
  bundle: true,
  minify: true,
  format: "iife",
  platform: "browser",
  target: "safari16",
  define: { "process.env.NODE_ENV": '"production"', __DEV__: "false" },
  plugins: [
    {
      name: "vava-web-platform",
      setup(bundler) {
        bundler.onResolve({ filter: /^react-native$/ }, () => ({
          path: resolve(root, "Web/platform.tsx"),
        }));
        bundler.onResolve(
          { filter: /^react-native-safe-area-context$/ },
          () => ({ path: resolve(root, "Web/safe-area.tsx") }),
        );
        bundler.onResolve({ filter: /^\.\/native$/ }, () => ({
          path: resolve(root, "Web/native.web.tsx"),
        }));
      },
    },
  ],
});
for (const file of ["index.html", "app.css"])
  await cp(resolve(root, "Web", file), `${out}/${file}`);
await cp(resolve(root, "Assets/Fonts"), `${out}/fonts`, { recursive: true });
await mkdir(`${out}/art`);
for (const item of await readdir(resolve(root, "Assets/Assets.xcassets"))) {
  if (!item.endsWith(".imageset")) continue;
  const folder = resolve(root, "Assets/Assets.xcassets", item);
  const metadata = JSON.parse(
    await readFile(`${folder}/Contents.json`, "utf8"),
  );
  const image = metadata.images.filter((image) => image.filename).at(-1);
  if (image)
    await cp(
      `${folder}/${image.filename}`,
      `${out}/art/${item.slice(0, -9)}.png`,
    );
}
const sources = {};
for (const folder of ["Web", "ReactNative"]) {
  for (const name of (await readdir(resolve(root, folder))).sort()) {
    sources[`${folder}/${name}`] = createHash("sha256")
      .update(await readFile(resolve(root, folder, name)))
      .digest("hex");
  }
}
sources["Scripts/build_web.mjs"] = createHash("sha256")
  .update(await readFile(fileURLToPath(import.meta.url)))
  .digest("hex");
await writeFile(
  `${out}/manifest.json`,
  JSON.stringify({ format: 1, sources }, null, 2) + "\n",
);
const archive = spawnSync(
  "python3",
  [
    resolve(root, "Scripts/package_web.py"),
    out,
    resolve(root, "Assets/LocalWeb/vava.zip"),
  ],
  { stdio: "inherit" },
);
if (archive.status !== 0) process.exit(archive.status || 1);
console.log("Packaged local Vava pages.");
