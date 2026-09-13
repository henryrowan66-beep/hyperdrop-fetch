# hyperdrop-fetch

Job runner for [HyperDrop](https://hyperdrop.hyperdrop-4bd713.workers.dev): give it a URL, GitHub Actions runs
`yt-dlp` (+ffmpeg) and uploads the result to the HyperDrop storage pool, then writes the player link to `results/<id>.json`.

## Submit a job
Push a file `jobs/<id>.json`:

```json
{ "url": "https://example.com/video-page", "name": "optional-output-name" }
```

or use **Actions → fetch-to-hyperdrop → Run workflow** and paste the URL.

## Read the result
`results/<id>.json` → `{ status: "ok", result: { view_url, direct_url, size_mb, shard } }` or `{ status: "failed", error }`.
The run's Summary tab shows the same JSON.

## Notes
- Only download content you own or are permitted to download. YouTube's terms prohibit downloading except where YouTube provides the feature.
- YouTube frequently blocks datacenter IPs (GitHub runners included) with "Sign in to confirm you're not a bot"; other sites generally work.
- Free tier: unlimited Actions minutes on public repos, 2,000 min/month on private ones. A typical fetch takes 1–3 minutes.
