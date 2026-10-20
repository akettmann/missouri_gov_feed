// Publish frontend/dist to a Google Cloud Storage bucket (run `pnpm build` first). Needs the gcloud CLI,
// logged in (`gcloud auth login`) with write access to the bucket.
//   MOGOV_SITE_BUCKET=my-bucket pnpm deploy:gcs            # sync, then set cache headers
//   MOGOV_SITE_BUCKET=my-bucket pnpm deploy:gcs --dry-run  # list what would change, touch nothing
// Files the build no longer produces are deleted from the bucket, so it always mirrors dist/.
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";

const bucket = process.env.MOGOV_SITE_BUCKET;
const dryRun = process.argv.includes("--dry-run");
if (!bucket) {
  console.error("Set MOGOV_SITE_BUCKET to the bucket name (without gs://).");
  process.exit(2);
}
if (!existsSync("dist/index.html")) {
  console.error("dist/ is missing or empty: run `pnpm build` first.");
  process.exit(2);
}

const dest = `gs://${bucket}`;
function gcloud(args) {
  console.log(`> gcloud ${args.join(" ")}`);
  const r = spawnSync("gcloud", args, { stdio: "inherit", shell: process.platform === "win32" });
  if (r.status !== 0) process.exit(r.status ?? 1);
}

gcloud([
  "storage",
  "rsync",
  "dist",
  dest,
  "--recursive",
  "--delete-unmatched-destination-objects",
  ...(dryRun ? ["--dry-run"] : []),
]);

if (!dryRun) {
  // hashed bundles never change; pages and data must pick up each refresh quickly
  gcloud([
    "storage",
    "objects",
    "update",
    `${dest}/_astro/**`,
    "--cache-control=public, max-age=31536000, immutable",
  ]);
  gcloud([
    "storage",
    "objects",
    "update",
    `${dest}/**.html`,
    "--cache-control=public, max-age=300, must-revalidate",
  ]);
  gcloud(["storage", "objects", "update", `${dest}/**.json`, "--cache-control=public, max-age=3600"]);
  console.log(`Published to ${dest}. Site URL depends on your bucket website / load balancer setup.`);
}
