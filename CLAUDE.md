# Ozzily — Project Context for Claude Code

## What this is

Ozzily (`ozzily.com`) is an SMS-first AI companion app for GLP-1 medication users
(Ozempic, Wegovy, Mounjaro, Zepbound). It texts users daily to keep them on top of
protein intake and resistance training, so they don't lose lean muscle mass while
losing weight on the medication.

**Positioning: warm and companion-feel, like Tomo.ai — NOT clinical, NOT aggressive.**
Brand identity: cute mascot, warm marigold/plum palette. Deliberately avoiding
generic AI-startup-template aesthetics.

### Name history (do not resurrect these)
- Previously called **ProteinPolice** — rejected for aggressive tone and a bad `.co` domain.
- Also rejected: Zempick ("-ick" sound), Ozzudo (syllable count / judo association).
- Any old docs, PRDs, or exports referencing "ProteinPolice" are historical —
  the product logic in them is still mostly valid, but replace the name and tone
  (aggressive → warm/supportive) wherever it shows up.

## Current build state (Week 1 foundation complete)

- Landing page built and accessibility-hardened: WCAG AA contrast, mobile hamburger
  nav, pricing disclosure copy.
- Deployed to Vercel from GitHub repo `hustle-grover/ozzily-landing`, live at
  `ozzily.com` (apex is primary, `www` 308-redirects to apex).
- Supabase backend: project ID `siblqlstyccysqryggtr` (us-east-1). Six tables:
  `users`, `messages`, `streaks`, `payments`, `affiliate_clicks`, `scheduled_messages`.
  RLS enabled on all tables with zero permissive policies — full lockdown. All
  access is server-side via Make.com using the `service_role` key; the `anon` key
  is deliberately unused.
- Twilio number `+1 415 969 2088` — 415 area code chosen to match Tomo.ai's
  positioning. Runs on the **Massive Impact Media Private Limited** account.
  Switched Sep 2026 from the old personal-trial number `+1 415 980 6160` (that
  number is dead — required a real registered business for A2P 10DLC). Account
  SID, auth token, and phone-number SID live in the Notion Credentials Vault —
  never in this repo.
- Notion Builder OS set up (Projects, Credentials Vault, Daily Log, Ideas Pipeline,
  Resources & Tools) — this is the centralized system across all of Pankaj's
  projects; prefer keeping cross-project tracking there over per-repo docs.

## Infrastructure & tooling

- GitHub org: `hustle-grover`. Vercel team (Hobby plan): `team_vjD4PWRmCP6Tuup31FFFAE7E`.
- Automation currently lives in **Make.com** (webhook + scenario based) — not in
  this repo's code. If a task involves "wiring a CTA to Make.com," the repo-side
  work is just making sure the form POSTs to the right webhook URL; the scenario
  logic itself is configured in Make's UI, not here.
- AI: GPT-4o (system prompt engineering in progress).
- Payments: Stripe (setup pending).

## On the horizon (pick up here)

1. Wire the four landing page CTAs to the Make.com webhook for phone number capture.
2. Build out the Make.com automation scenarios (onboarding, vision AI photo
   verification, trial expiration, scheduled check-ins).
3. Engineer the GPT-4o system prompt (warm/supportive tone, not the old
   aggressive ProteinPolice tone — strict on no medical/dosing advice).
4. Set up Stripe billing (3-day trial → $29/month).

## Hard-won technical learnings

- Supabase function security: `revoke all on function from anon, authenticated`
  alone is **not enough** — Postgres grants EXECUTE to PUBLIC by default. Correct
  pattern:
  ```sql
  revoke all on function <name> from public, anon, authenticated;
  grant execute on function <name> to service_role;
  ```
- Use `get_advisors` for iterative security hardening after any migration.
- Ship over tooling overhead: the landing page was deployed as a straight HTML/
  Vercel prototype rather than building it in Framer — bias toward shipping.

## How Pankaj wants this worked

- **Execute directly.** Create schemas, deploy, update Notion, etc. — don't just
  hand back step-by-step instructions to run manually.
- **Push back when there's a better path.** He wants honest, direct opinions over
  hedged advice, including disagreement with the original plan.
- Iterate through accessibility/quality audit passes before calling a component done.
- Keep credentials and project tracking centralized in Notion — not scattered in
  ad hoc per-project notes.
- Descriptive, organized file names by default.
- Milestone-gated style: one clear deliverable at a time, verified before moving on.

## Secrets

Supabase `service_role` key, Twilio SID/auth token, and Stripe keys live in a local
`.env` (gitignored) — never in this file, never committed.
