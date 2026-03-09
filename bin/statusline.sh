#!/bin/bash
# Claude Code Status Line
# Single-line status bar with model, project, duration, cost, context, lines changed, and rate limit bars.
# Uses Node.js for JSON parsing and ANSI color output — no jq dependency.
#
# Install:
#   cp bin/statusline.sh ~/.claude/statusline.sh
#   Add to ~/.claude/settings.json:
#   { "statusLine": { "type": "command", "command": "bash ~/.claude/statusline.sh" } }
#
# Configuration (environment variables):
#   STATUSLINE_SHOW_COST=true       Show session cost ($X.XX)
#   STATUSLINE_SHOW_LINES=true      Show lines added/removed (+N/-N)
#   STATUSLINE_SHOW_RATE_LIMITS=true Show 5-hour and weekly usage bars
#   STATUSLINE_SHOW_PACE=true       Show weekly pace indicator (1.2x)
#   STATUSLINE_CONTEXT_ICON=✍️       Icon before context percentage
#   STATUSLINE_CACHE_TTL=300        Seconds to cache rate limit API response
#   STATUSLINE_BAR_WIDTH=10         Width of rate limit progress bars

node -e '
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

let chunks = [];
process.stdin.on("data", c => chunks.push(c));
process.stdin.on("end", () => {
  try {
    const d = JSON.parse(chunks.join(""));

    // ── Configuration ──────────────────────────────────────────────
    const env = process.env;
    const cfg = {
      showCost:       env.STATUSLINE_SHOW_COST !== "false",
      showLines:      env.STATUSLINE_SHOW_LINES !== "false",
      showRateLimits: env.STATUSLINE_SHOW_RATE_LIMITS !== "false",
      showPace:       env.STATUSLINE_SHOW_PACE !== "false",
      contextIcon:    env.STATUSLINE_CONTEXT_ICON || "\u270D",
      cacheTtl:       parseInt(env.STATUSLINE_CACHE_TTL || "300", 10),
      barWidth:       parseInt(env.STATUSLINE_BAR_WIDTH || "10", 10),
    };

    // ── ANSI Colors ────────────────────────────────────────────────
    const purple = "\x1b[38;2;167;139;250m";
    const blue   = "\x1b[38;2;96;165;250m";
    const green  = "\x1b[38;2;52;211;153m";
    const yellow = "\x1b[38;2;251;191;36m";
    const orange = "\x1b[38;2;249;115;22m";
    const red    = "\x1b[38;2;239;68;68m";
    const gray   = "\x1b[38;2;107;114;128m";
    const dim    = "\x1b[2m";
    const reset  = "\x1b[0m";
    const sep    = ` ${dim}\u2502${reset} `;

    // ── Model ──────────────────────────────────────────────────────
    const model = d.model?.display_name || "Unknown";

    // ── Project ────────────────────────────────────────────────────
    const project = d.workspace?.project_dir
      ? require("path").basename(d.workspace.project_dir)
      : "Unknown";

    // ── Session Duration ───────────────────────────────────────────
    const ms = d.cost?.total_duration_ms || 0;
    const totalSec = Math.floor(ms / 1000);
    const h = Math.floor(totalSec / 3600);
    const m = Math.floor((totalSec % 3600) / 60);
    let dur;
    if (h > 0) dur = h + "h" + (m > 0 ? m + "m" : "");
    else if (m > 0) dur = m + "m";
    else dur = totalSec + "s";

    // ── Cost ───────────────────────────────────────────────────────
    const costVal = d.cost?.total_cost_usd || 0;
    const cost = "$" + costVal.toFixed(2);

    // ── Context Window ─────────────────────────────────────────────
    const ctxSize = d.context_window?.context_window_size || 200000;
    const usage = d.context_window?.current_usage || {};
    const tokens = (usage.input_tokens || 0)
      + (usage.cache_creation_input_tokens || 0)
      + (usage.cache_read_input_tokens || 0);
    const pct = Math.round(tokens * 100 / ctxSize);
    let ctxColor = green;
    let ctxStr = pct + "%";
    if (pct >= 70) { ctxColor = red; ctxStr = "[!!] " + pct + "%"; }
    else if (pct >= 50) { ctxColor = orange; ctxStr = "[!] " + pct + "%"; }

    // ── Lines Changed ──────────────────────────────────────────────
    const added = d.cost?.total_lines_added || 0;
    const removed = d.cost?.total_lines_removed || 0;

    // ── Rate Limit Bars ────────────────────────────────────────────
    let barStr = "";
    if (cfg.showRateLimits) {
      try {
        const home = process.env.HOME || process.env.USERPROFILE;
        const cacheFile = path.join(home, ".claude", "usage-cache.json");
        let usageData = null;

        // Read cache (use stale data while revalidating)
        let cacheAge = Infinity;
        try {
          const stat = fs.statSync(cacheFile);
          cacheAge = (Date.now() - stat.mtimeMs) / 1000;
          usageData = JSON.parse(fs.readFileSync(cacheFile, "utf8"));
        } catch(e) {}

        // Only fetch if cache is expired AND no other fetch is in progress
        if (cacheAge >= cfg.cacheTtl) {
          const lockFile = cacheFile + ".lock";
          let shouldFetch = false;
          try {
            // Atomic lock: create exclusively, fails if exists
            fs.writeFileSync(lockFile, String(Date.now()), { flag: "wx" });
            shouldFetch = true;
          } catch(e) {
            // Lock exists — check if stale (>30s means previous fetch crashed)
            try {
              const lockAge = (Date.now() - fs.statSync(lockFile).mtimeMs) / 1000;
              if (lockAge > 30) {
                fs.unlinkSync(lockFile);
                fs.writeFileSync(lockFile, String(Date.now()), { flag: "wx" });
                shouldFetch = true;
              }
            } catch(e2) {}
          }

          if (shouldFetch) {
            try {
              const credsPath = path.join(home, ".claude", ".credentials.json");
              const creds = JSON.parse(fs.readFileSync(credsPath, "utf8"));
              const token = creds.claudeAiOauth?.accessToken;
              if (token) {
                const result = execSync(
                  "curl -s -H \"Authorization: Bearer " + token + "\" " +
                  "-H \"anthropic-beta: oauth-2025-04-20\" " +
                  "\"https://api.anthropic.com/api/oauth/usage\"",
                  { timeout: 5000, encoding: "utf8" }
                );
                const parsed = JSON.parse(result);
                if (parsed && !parsed.error) {
                  usageData = parsed;
                  fs.writeFileSync(cacheFile, result);
                }
              }
            } finally {
              try { fs.unlinkSync(lockFile); } catch(e) {}
            }
          }
        }

        if (usageData) {
          function buildBar(pctVal, width) {
            const filled = Math.round(pctVal * width / 100);
            const empty = width - filled;
            let color;
            if (pctVal >= 90) color = red;
            else if (pctVal >= 70) color = yellow;
            else if (pctVal >= 50) color = orange;
            else color = green;
            return color + "\u2588".repeat(filled) + dim + "\u2591".repeat(empty) + reset;
          }

          const fiveHourPct = Math.round(usageData.five_hour?.utilization ?? 0);
          const weeklyPct   = Math.round(usageData.seven_day?.utilization ?? 0);

          barStr = sep + gray + "5-hour " + reset
            + buildBar(fiveHourPct, cfg.barWidth) + " " + gray + fiveHourPct + "%" + reset;
          barStr += sep + gray + "weekly " + reset
            + buildBar(weeklyPct, cfg.barWidth) + " " + gray + weeklyPct + "%" + reset;

          // Weekly pace indicator
          if (cfg.showPace) {
            const weeklyReset = usageData.seven_day?.resets_at;
            if (weeklyReset && weeklyPct > 0) {
              const resetMs = new Date(weeklyReset).getTime();
              const nowMs = Date.now();
              const windowMs = 7 * 24 * 60 * 60 * 1000;
              const remainMs = resetMs - nowMs;
              const elapsedMs = windowMs - remainMs;
              const elapsedPct = Math.max(1, Math.min(100, elapsedMs * 100 / windowMs));
              const pace = weeklyPct / elapsedPct;

              let paceColor;
              if (pace >= 1.5) paceColor = red;
              else if (pace >= 1.1) paceColor = orange;
              else if (pace >= 0.9) paceColor = yellow;
              else paceColor = green;

              barStr += " " + paceColor + pace.toFixed(1) + "x" + reset;
            }
          }
        }
      } catch(e) {
        // Rate limit fetch failed — skip bars silently
      }
    }

    // ── Assemble ───────────────────────────────────────────────────
    let line = purple + model + reset + sep + blue + project + reset;
    line += sep + gray + dur + reset;
    if (cfg.showCost) {
      line += sep + yellow + cost + reset;
    }
    line += sep + yellow + cfg.contextIcon + reset + " " + ctxColor + ctxStr + reset;
    if (cfg.showLines && (added > 0 || removed > 0)) {
      line += sep + green + "+" + added + reset + red + "/-" + removed + reset;
    }
    line += barStr;

    console.log(line);
  } catch(e) {
    console.log("Status: " + e.message);
  }
});
'
