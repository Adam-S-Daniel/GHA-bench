<!-- BEGIN MANAGED SECTION — DO NOT EDIT ABOVE "## Repo-specific additions" -->
<!-- Source: _agent-guidance -->
<!-- Sections: none -->

# AGENTS.md

> **Managed by [`_agent-guidance`].**
> Edit only below the `## Repo-specific additions` header.
> Everything above it will be overwritten on the next sync.

This block is deliberately short. It carries the things that are **specific to
this account and learned the hard way** — incidents, fleet policy, machine
layout. It does not restate general engineering practice, and it does not
describe anything you can learn by reading the repo. Depth lives in each repo's
`docs/` and in the skills registry; follow the pointers when the work touches
that area.

## Working in these repos

- Fix what was asked. No speculative features, premature abstractions, or
  unused helpers.
- Prefer editing an existing file over creating a new one.
- Every public interface change updates the corresponding tests.
- Run the existing test suite before calling a task complete, and say plainly
  what you ran. New behaviour gets a test; a bug fix gets a regression test.
- Tests must be deterministic — no sleeps, no network, no reliance on
  wall-clock time.

## An approval you name gets its link

Never hand back "waiting on your approval", "needs sign-off", "pending review"
or "blocked on a gate" without the URL of the thing to click. A noun is not
something the operator can act on, and the one who wrote the sentence is the one
holding the run id. (Real incident, 2026-08-27: a session reported
jodidaniel.com#176 as waiting on a human approval across three consecutive
turns, each time declining to act on it and each time naming no location. The
operator's next message was "What human approval? Link me.")

- **Link the surface that actually decides, not its parent.** A required
  environment review lives on its own job page,
  `.../actions/runs/<run_id>/job/<job_id>` — the PR only shows that it is
  pending. Resolve the run that is `waiting` on the CURRENT head; a link
  carried over from an earlier head points at a gate that no longer governs
  anything.
- **Give every surface when there is more than one, and say which you
  verified.** The platform's regression gate is approvable from GitHub Actions
  *and* from the site's own `/admin/reviews/` dashboard, and an operator may
  hold only one of them.
- The rule is not specific to approvals: anything you hand over as the
  operator's move — a PR to merge, a red run to look at, a setting to flip, a
  dashboard to read — is named with its URL in the same sentence.
- **It governs what YOU are waiting on, not only what you hand over.** "waiting
  on CI", "the sync is running", "once the verifier finishes" each name a thing
  the operator may want to watch right now, and the one who started it is the one
  holding its id. Link every in-flight thing you name, every time you name it —
  the run, the PR, the scheduled check-in — not once when you start it and never
  again. A status update whose nouns cannot be clicked has handed the operator a
  feeling of progress and no way to check it.
- **When the thing has no URL, say that, and give what it does have.** A local
  background task, a subagent, a file on a machine only you can see: name it, say
  plainly that there is no link, and give the id and the output path. "No link —
  local task `abc123`, output at `/tmp/…`" satisfies the rule. "I'm waiting on
  the verifier" does not, and is worse than silence, because it reads as
  something the operator could go and look at.
- **Stop waiting out loud when you stop waiting.** A check-in scheduled against a
  PR that has since merged, a watch on a closed issue, a poll for a run that
  finished — cancel it and say so. Naming a blocker that is no longer blocking is
  the same defect pointed at the past.

## Finding your unknowns

Output quality on a non-trivial task is bounded by how well the ambiguities got
resolved — and most of them surface *during* implementation, not before it. So
treat unknown-hunting as part of the work, not a phase that ends at the plan:

- Before building: name what you don't know. Prefer a reference in **code** — an
  existing implementation to mirror, a failing test, a rubric, an HTML mockup —
  over a prose description of the same thing.
- While building: keep a running note of decisions that departed from the plan
  and edge cases you hit. Surface them; don't silently absorb them.
- After building: be able to explain what changed and why it is correct.
- Durable findings go in the **repo**, not in agent memory — an environment
  quirk, non-obvious wiring, where a source of truth actually lives, a
  sequencing constraint. Repo files version with the code and every person and
  every harness that opens the repo sees them; agent memory is per-agent and is
  silently missed by the next session. A fleet-wide rule goes in
  `_agent-guidance`'s `agents-md/base.md`, a repo fact below the
  `## Repo-specific additions` marker, a reusable procedure into the skills
  registry. A memory note is a supplement, never the only copy.

The full workflow (blind-spot pass, self-interview, implementation notes,
post-hoc explainer) is the **`finding-unknowns`** skill in the registry. Reach
for it on unfamiliar code, a new domain, or anything with subjective acceptance
criteria.

## Workstation layout

Repo locations are host-specific — match the convention of the machine you're on
(on Windows, check `$env:COMPUTERNAME`).

- **`ZENDA`** (Windows): local clones live under `D:\repos\<github-owner-or-org>\<repo>`
  (for example `D:\repos\adam-s-daniel\wsl-automation`). Clone new repos there, and
  assume existing repos live there rather than under the user profile
  (`C:\Users\<user>\...`).

## Sessions get cut off

**`ZENDA` drops sessions mid-task, frequently.** Assume any run can end between
one tool call and the next, and keep the work recoverable throughout rather
than only at the end.

- **Commit and push as you go**, on a branch. A pushed branch survives the
  laptop; the conversation, a dirty tree and a worktree do not — a worktree can
  be deleted with the session that made it. Small commits *are* the checkpoint.
- **Persist the expensive part**, which is the investigation and not the diff:
  the root cause, the baseline test result, the option already ruled out. A
  fresh session can regenerate a patch quickly; it cannot cheaply re-derive why
  the obvious fix was wrong. Put it in the commit message, the PR body, or an
  ADR — all of which outlive the context window. Chat does not.
- **Say where things stand before a long step** — a full test suite, a CI
  watch, a wide refactor — so a resumed session starts from a statement of what
  is done and what is next, not a reconstruction of it.
- **Report a resume pointer, not just an outcome:** branch, PR number, worktree
  path, and the next command to run.

## Security

Standard practice applies without being restated here. These are the ones with
teeth in this account:

- Validate anything that crosses a trust boundary — user input, API responses,
  file contents.
- Never build SQL, shell commands, or HTML by string-concatenating untrusted
  data. Use parameterized queries, shell arrays, and context-aware escaping.
- Never commit secrets, credentials, or `.env` files.
- Never disable TLS verification, authentication, or CSRF protection.

## Data exposure in CI and public repos

Treat CI run logs, job summaries, artifacts, workflow run pages, and git history
as **public** on a public repo. (Real incident: a workflow printed the owner's
email addresses and their correspondents' into a public Actions log.)

- **Never print personal or sensitive data to a log** — no emails, contacts,
  names, IDs, mailbox sizes/counts, tokens, or anything "useful to an attacker or
  scammer." Deliver sensitive results out-of-band (e.g. email the account itself,
  write to a private store) and log only a non-identifying status line.
- **Don't interpolate `${{ inputs.* }}` / `${{ github.event.* }}` into a `run:`
  block** — the rendered command is echoed to the log. Read inputs from
  `$GITHUB_EVENT_PATH` inside the script and `::add-mask::` sensitive values
  before use. `::add-mask::` only scrubs the log *stream*, not other surfaces.
- **Put sensitive config in secrets, not plaintext inputs or `vars`.** Only
  secret *values* are masked in logs.
- **Sanitize error output** — never dump an API/HTTP response body on failure (it
  can quote personal data); reduce it to a status code + machine error type, and
  keep the data-bearing serialization/call inside the try/catch.
- **Least privilege:** set `permissions:` to the minimum (usually
  `contents: read`) and require approval for outside-collaborator fork PRs.
- **Test fixtures use reserved `example.com` / `example.net` domains only** —
  never a real address; fixtures get committed and logged.

### git history & metadata
- **Sanitize before the first commit.** Fixing the current file does not remove
  data from history. If sensitive data was committed, rewrite history to drop the
  commits, delete every ref that points at them (branches, tags, **PRs**), and
  force-push. GitHub garbage-collects unreachable objects on its own schedule
  (days to weeks) — until then they remain reachable *by SHA* — and you can ask
  GitHub Support to expedite for a public repo. (This is the deliberate exception
  to "don't force-push"; it is a security remediation.)
- **Commit with the GitHub `…@users.noreply.github.com` identity** on public
  repos so a real email is not baked into commit author/committer metadata.

## Network allowlists live in `_agent-guidance/docs/reference/`

Two egress allowlists are kept there as **reference copies**, each with a
sidecar changelog carrying the per-domain justification an allowlist line has
no room for. Neither is loaded by anything — read them when you are changing
one, and add a changelog entry when you do.

- `network-allowlist-claude-environments.txt` — the domain list in force in the
  Claude Code cloud environment named `My Whitelist`. **In force**; the
  authoritative copy is the environment dialog at claude.ai/code, and this file
  tracks it.
- `network-allowlist-github-runners.txt` — a **proposed** list for CI. Not
  enforced anywhere and not enforceable on a standard runner: GitHub-hosted
  runners have unrestricted egress, and roadmap #821 for native outbound
  control is closed as not planned.

Each `.txt` has a `.CHANGELOG.md` beside it whose header states what an entry
must carry. Two traps both files exist to record: a `*.example.com` line does
**not** match the apex `example.com`, and the Claude environment's "also
include default list of common package managers" checkbox silently adds ~200
more domains, so a line that looks missing may be covered by it.

## Automation vs branch protection

Fleet repos enforce PR-only default branches via ruleset, managed as code in
`repo-settings` (see its ADR 0001). Design automation accordingly:

- Never design a bot that pushes to a protected default branch ad hoc — the
  push is rejected (GH013), even from the repo's own workflows.
- Generated data (badges, run summaries, reports, dashboards) belongs on a
  dedicated unprotected results branch (e.g. skills-evals' `eval-results`);
  consumers read from that branch and treat its content as untrusted.
- The rare bot that genuinely must write to a default branch needs a ruleset
  bypass actor declared in repo-settings' `fleet.yml` — never a hand-granted
  UI bypass (the drift report flags those). The AGENTS.md sync App is the
  standing example.
- PR + auto-merge is not a sanctioned bot-write path for fleet repos; the
  cms-platform-managed repos (outside the fleet ruleset) use it by their own
  design.

### A required status check gets no `concurrency` group

A job that publishes a **required** status context and can fire more than once
on the same head sha — label events, an `opened` + `synchronize` burst, any
multi-event trigger — gets no `concurrency` block at all.

- GitHub picks **non-deterministically** between a cancelled run and a
  successful one for the same context + sha. When cancelled wins the PR is hard
  blocked: the merge API returns `405 Required status check "<ctx>" is
  cancelled`, and nothing overrides it — not native auto-merge, not an explicit
  merge call, not a nudge bot. The PR looks all-green and simply never lands.
- **`cancel-in-progress: false` is not "run them all."** GitHub keeps the
  in-progress run plus only the *latest* pending run in the group and cancels
  the other pending duplicates, so a same-sha burst still leaves cancelled runs
  behind. Flipping that flag is the fix that looks right and changes nothing.
- Same mechanic on any shared lane: when one push drives two workflows into one
  group, the older pending sibling is cancelled. Make the triggers pairwise
  disjoint — a shared group only serialises runs that already arrive apart.
- Jobs triggered only by `push` / `synchronize` — each a new sha — are safe to
  cancel and keep `cancel-in-progress: true`.
- Lock the invariant with a test that **parses** the workflow YAML (the `yaml`
  package — never a regex or line scan, which reads clean on text it cannot
  see), so the block cannot come back.

## Two GitHub connectors, and which one you are holding

A session here can see **two** GitHub MCP servers at once. They authenticate as
the same person, so `get_me` will not tell them apart, and the tool names do
not say which is which. Establish it before you reach for one:

- **`mcp__github__*` — session-provisioned.** It does NOT appear in
  `ListConnectors`; the remote environment supplies it and the session's own
  system prompt points at it. It is the **only** one with GitHub Actions tools
  (`actions_list`, `actions_get`, `actions_run_trigger`), workflow-run and
  job-log introspection (`get_check_run`, `get_job_logs`), auto-merge control,
  and review-thread resolution. Read that as the ACTIONS side specifically, not
  as "all CI reads" — the next bullet is where a pull request's own check runs
  live. Its reach is the session's attached repositories; `add_repo` widens it
  mid-session.
- **`mcp__github-mcp__*` — the claude.ai org connector `github-mcp`.** It lists
  in `ListConnectors` as `connected: true`. Its tool set is a **strict subset**
  of the above: same reads, same PR and issue writes, same `merge_pull_request`,
  `push_files` and `delete_file` — and no Actions, no job logs, no auto-merge,
  no review threads. Its reach comes from a GitHub App installation allowlist
  that is INDEPENDENT of the session's attached repos. **Probe for it by
  connector NAME, never by that prefix from memory.** This file named it
  `mcp__b26ebb34-…__*` until 2026-08-28, when a live session measured it as
  `mcp__github-mcp__*`; a run that searches its tools for the remembered
  literal matches nothing, concludes "no connector present", and stands down
  with a fully working one sitting right there. The prefix has moved once
  already — assume it can move again, and probe both forms by name.

Three consequences, and the first is why this section sits where it does:

- **The CI boundary runs through the middle of the org connector, not around
  it.** It CAN check a pull request: `pull_request_read` accepts
  `method: "get_check_runs"` (the head commit's check runs, with their
  conclusions) and `method: "get_status"` (the combined commit status).
  Measured 2026-08-28 against `_agent-guidance` #83 — four check runs came
  back, `success` and `skipped`. What it genuinely lacks is the **Actions**
  side: no `actions_list` / `actions_get` / `actions_run_trigger`, no
  `get_check_run`, no `get_job_logs` — so it cannot dispatch a workflow, read
  a workflow RUN, or pull a failed job's log — and with no
  `enable_pr_auto_merge` a merge under it is synchronous (check, then merge,
  in the same run) rather than armed and walked away from. Read BOTH methods,
  for the reason `"The watch finished" is not "CI passed"` gives below: #83
  answered `get_status` with `pending` over zero statuses at the same moment
  every check run on it was green, so either method read alone misreports.
  This bullet used to say the org connector "can merge a pull request but it
  cannot check one" — wrong, and wrong in the expensive direction, because it
  tells an org-connector-only session that it must not merge and so disables
  a capability the operator deliberately granted it.
- **Fewer tools is not less dangerous.** Both connectors merge, push and
  delete. The subset one is the connector whose reach you cannot infer from the
  session's repo list, so a write through it can land somewhere the session was
  never scoped to. Measured 2026-08-19: `github-mcp` 404s on the private
  `repo-settings` even though the account can push there, while both read a
  public non-attached repo fine.
- **A 404 means "not visible to THIS connector"** — never that a repo or file
  does not exist. Re-check on the other one before concluding anything; the
  next section is how to tell the two apart.

Prefer `mcp__github__` for everything. Reach for `github-mcp` only when the
other genuinely cannot see a repo, and say so out loud when you do. When you
report a verification, name the connector it came from.

## A GitHub 404 means "not authorized", not "not there"

GitHub answers **404 rather than 403** when a caller is not authorized to know a
private repo exists — it will not confirm the repo either way. So a 404 from any
GitHub API or MCP call is ambiguous by design: either the thing is gone, or the
credential simply lacks that repo. The body says "Not Found" in both cases,
which is why the wrong reading — telling someone their PR was deleted — is the
easy one to reach for.

- **Probe the repo, not the object.** If `GET /repos/<owner>/<repo>/pulls` 404s
  as well, the whole repo is invisible to that credential: a scope gap, not a
  missing PR. If the repo answers and only the object 404s, it is genuinely
  gone.
- **Try the other connector before concluding anything.** The two servers above
  do not share an installation, so one can be blind to a repo the other reads
  fine. (Real incident, 2026-08-19: a mid-session MCP reconnect brought up a
  second GitHub server whose credential could not see a private repo. Every call
  against it 404ed — including on a PR the *other* connector had read
  successfully minutes earlier — and the repo was neither deleted nor unshared.
  `add_repo` reported it already attached, which is about session scope and does
  not widen a connector's own installation.)
- **Git is a separate credential path** and often still works when the API
  token does not. `git ls-remote origin '<ref>'` answers "does this branch
  exist"; `git merge-base --is-ancestor <sha> origin/main` answers "was it
  merged". Neither touches the API, so both stay available to report real state
  while a connector is blind.
- Never report a repo, PR, or branch as gone on a 404 alone. Say which
  credential could not see it, and what you checked with.

## The fleet spans TWO owners, and a scoped search will not say so

`Adam-S-Daniel` and `jodidaniel`. Both are named in `SYNC_OWNERS` in
_agent-guidance's `sync.yml`, `drift-report.yml` and `skills-lock-bump.yml`,
and every fleet-wide script reads that variable rather than assuming one owner.
An ad-hoc query that does assume one is answering a narrower question than the
one you asked — and it answers it confidently.

That is what makes this worse than the 404 above. A 404 at least looks like a
problem. A search scoped to one owner returns a **plausible, complete-shaped
result set**: no error, no empty page, nothing to prompt a second look.

Measured 2026-08-25: `search_code filename:skills.lock user:Adam-S-Daniel`
returned five repos, and that became a report that jodidaniel.com "has NO
`skills.lock`, so it receives no bundles at all." It had one — a federated lock
of 22 skills, the bootstrap hook, and the `settings.json` wiring. The repo is
`jodidaniel/jodidaniel.com`, so the query could not have found it under any
circumstances. `repos.yml` also said `lock: committed` in plain English, one
`grep` away.

- **Enumerate owners; never hardcode one.** `SYNC_OWNERS` is the list, and it
  is two long today precisely so nobody has to remember that it is.
- **Prefer the fleet's own registries to a search index.** `repos.yml`,
  `fleet.yml` and `cron_coverage.fleet` are lists a human maintains and CI
  checks. A code-search result is a snapshot of an index that is not
  exhaustive even within one owner — a zero result is weak evidence in a way a
  missing entry in one of those files is not.
- **To ask whether repo X has file Y, ask the repo.** `git ls-remote`, a
  shallow clone, or the contents API answers about the repo; a search answers
  about the index.
- **Your session's reach is not the fleet's shape.** Tooling may be scoped to
  one owner — hosted sessions refuse cross-owner repo attachment — so "I cannot
  see it" and "it does not exist" have to stay separate sentences. Say which
  one you mean, and say what you checked with.

## "The watch finished" is not "CI passed"

Never read CI pass/fail off a watch command's exit code, or off the fact that it
returned. Three failure modes stack: in `cmd | tail` the shell's `$?` is
`tail`'s — always 0 — masking the non-zero from `gh pr checks`; a backgrounded
watch reports that same pipeline code, so its "completed (exit code 0)"
notification says nothing about the build; and `tail -N` can show only the
passing and skipping lines while the FAILURE lines scrolled out of the window,
so eyeballing it looks green too. (Real incident: all three lined up on one PR —
e2e and lint were FAILURE while the session reported CI green and moved on.)

- Capture the real code with `${PIPESTATUS[0]}`, or don't pipe the watch at all.
- After **any** CI watch, query the conclusions explicitly and report the parsed
  result before acting on it:

  ```bash
  gh pr view <n> --repo <owner>/<repo> --json statusCheckRollup --jq \
    '.statusCheckRollup[] | (.conclusion // .state) as $c
     | select($c != null and $c != "SUCCESS" and $c != "NEUTRAL")
     | "\(.name // .context): \($c)"'
  ```

  A check run carries `.conclusion`, a legacy commit status carries `.state` —
  filter on only one and the other's failures read as clean.
- Treat "watch done" as "now verify", never as "passed". Don't launch a watch
  and go passive without a definite verify-the-rollup step on resume.

### A pipe into `grep -q` is a race, and one passing test proves nothing

`echo "$big" | grep -q` under `pipefail` is the same trap with a timer on it.
`grep -q` exits at the first match; once the payload passes the 64 KiB pipe
buffer the writer still has bytes to write, takes SIGPIPE, and `pipefail` turns
141 into a false negative — a marker that IS present reads as absent.

It defeated its own investigation for a week (issue #81), because the disproof
was one probe per size. Twenty trials per size against the real file: 48 kB
0/20, 56 kB 0/20, 64 kB 0/20, 72 kB 2/20, 95 kB 18/20. At 95 kB a single shot
passes about one time in ten, which is exactly what that issue recorded as
"passed at every size". In production it presented as the largest `AGENTS.md`
in the fleet, and only that one, reporting false drift.

- **Feed the data as an argument or a here-string, never through a pipe** into
  a command that exits early: `grep -qxF -- "$m" <<<"$s"`, or `grep -qxF -- "$m"
  file`, or pure bash `[[ $'\n'"$s"$'\n' == *$'\n'"$m"$'\n'* ]]`.
- **A size-dependent bug needs trials, not a probe.** If what you are clearing
  could be a race, one green run is not evidence — say how many trials you ran.
- The same shape is safe when the value is captured inside `$( ... || true )`,
  because the status is discarded. That is correct by accident, so say so where
  you find it rather than leaving the next reader to re-derive it.

## A successful `git push` does not mean your commit exists

Same shape as the trap above — an exit code that belongs to a different command
than the one you meant to measure — but it bites at the other end of the cycle,
and it is worse because the artifact it leaves behind looks finished.

A pre-commit hook that refuses the commit does not stop the push. `git commit`
exits non-zero and writes nothing; the `git push` that follows then pushes the
branch at whatever HEAD still is — the base commit — and prints exactly what a
real push prints:

```
 * [new branch]      claude/my-branch -> claude/my-branch
branch 'claude/my-branch' set up to track 'origin/claude/my-branch'.
```

The branch is real, a PR can be opened on it, and the diff is empty. Nothing in
the push output is false; it just answers a question you did not ask.

**This is a hosted-session problem specifically.** The fleet's `secrets-scan`
pre-commit guard (delivered by cms-platform's `dev-hooks-sync.yml`) requires
`gitleaks` on `PATH` and FAILS CLOSED when it is missing — correctly, since a
security gate that skips when absent is not a gate. A fresh container has no
`gitleaks`, so every commit in one is refused until you install it. (Measured
2026-08-25 on adamdaniel.ai: the hook printed its install instructions, the
commit never happened, `git push -u` reported a new branch, and
`git log --oneline -1` was still the base merge commit.)

- **Verify the commit, not the push.** `git log --oneline -1` should show your
  message, and `git status --short` should be clean. Or compare directly:
  `git rev-parse HEAD` must differ from `git rev-parse origin/<base>`.
- **`&&`-chain commit into push** so a refused commit stops the chain. A
  newline or `;` between them does not — that is what turns a blocked commit
  into a pushed branch.
- **Install the tool; do not reach for the bypass.** `SKIP_SECRETS_SCAN=1`
  exists for an emergency, and a missing binary in a container you control is
  not one — a release binary is one `curl` away, and CI scans the PR either
  way, so bypassing locally only moves the finding later.

## Dependency updates

Dependabot runs with a **minimum package age** (`cooldown`) so an unattended
merge still gets a cooling-off period: `default-days: 7`, `semver-major-days: 30`.
Two things about that setting are easy to get wrong:

- It applies to **version** updates only. A security advisory bypasses cooldown
  entirely and opens immediately — the wait never delays a vulnerability fix.
- An unset `cooldown` is **not** "no wait": GitHub applies an implicit 3-day
  minimum age to version updates. Writing 7 is a raise from 3, not from zero.

`semver-minor-days` / `semver-patch-days` are deliberately left undefined —
they fall back to `default-days`, and spelling them out only invites drift.

The window is not only Dependabot's. A package you add or bump **by hand** mid-task
is the case with no automation watching it: check the publish date
(`npm view <pkg> time --json`), take the newest release that has already cleared
the 7 days rather than the freshest one, and pin it exact (no caret) so `npm ci`
cannot drift onto a version that has had no cooling-off at all.

## A name you choose becomes data a scanner reads

gitleaks' `generic-api-key` rule fires on a **keyword** next to a
high-entropy value. The keyword list is short and ordinary:

```
access  auth  api  credential  creds  key  passwd  password  secret  token
```

Nothing warns you that those words are reserved, because they are not — they
are only reserved *in the position a scanner looks at*. Name a skill, a config
key, a job output, an artifact or a fixture with one of them, and every
generated file that serialises `name: value` alongside a hash, id or digest
starts looking like a leak.

That is not hypothetical. A skill named **`cms-platform-secrets`** put the line
`"cms-platform/cms-platform-secrets": "<64-hex>"` into `skills.lock`, which is
generated, committed, and scanned. Both consumer sites went red on every push
to `main` — adamdaniel.ai for eight consecutive pushes, each one a blocked
editorial publish. An audit of all 34 skill names across both registries found
exactly one hit: that name. One word, one outage.

The shape that makes it hard to catch:

- **The repo that chooses the name is not the repo that breaks.** cms-platform
  named the skill; the two sites that install its bundle are what went red.
  cms-platform's own lock lists only `adam/*` skills, so it stayed green and
  the author had no signal at all.
- **A pull request cannot see it.** The PR lane scans `base..head`; the push,
  schedule and dispatch lanes scan full history. A finding that lives in an
  older commit is invisible to every PR and fires on every push.
- **History is immutable, so the name outlives the rename.** Fixing the
  generator or renaming the skill fixes the working tree and nothing else. The
  old line stays in every clone until history is rewritten.

So:

- **Check a name against that list before you commit to it**, whenever the name
  will land in a generated or serialised artifact. It costs one grep. Prefer a
  name that says what the thing is for over one that names the sensitive noun —
  `consumer-repo-provisioning` carries the same meaning as
  `cms-platform-secrets` and trips nothing.
- **Fix it at the source, not with an allowlist.** An allowlist entry is
  per-repo; a `.gitleaksignore` fingerprint is `<commit>:<file>:<rule>:<line>`
  and commit shas are repo-unique, so it cannot be propagated *at all* — copied
  to another repo it names a commit that does not exist there and silently
  suppresses nothing while looking like coverage. One rename immunises every
  consumer at once; N exclusions immunise N repos until the next one adopts.
- **Do not lean on a scanner's internals.** Labelling a digest `sha256:<hex>`
  currently dodges the rule because `:` falls outside its capture class — a
  welcome side effect, and a bad thing to depend on. Justify such a label as
  self-documentation (it says which algorithm produced the digest); if the
  upstream regex ever widens, every lock in the fleet goes red at once.
- **Suppress by value, never by path.** A `paths` entry does not filter
  findings, it skips the file before any rule runs, so a real credential pasted
  into it is never reported (cms-platform#260 — 29KB of a public repo left
  unscanned that way, suppressing nothing that the value regexes did not
  already cover).

## Pinning GitHub Actions

**Every `uses:` is pinned to a full 40-character commit SHA** — in workflows,
composite actions, and reusable-workflow references alike. The one carve-out,
named below, is a ref into this account's own `cms-platform`, and it covers both
of the shapes such a ref takes. Never a tag, never a branch, never an
abbreviated SHA. A tag is a movable pointer: pinning to one gives whoever can
retag the upstream repo a shell on the runner, holding that job's token.

```yaml
uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11
```

- **A pin carries NO trailing version comment.** `@<sha>` and nothing after it.
  The argument for one is intuitive and will be re-derived by the next person, so
  here is why it lost: forty hex characters do say nothing on their own, but the
  comment is not maintained by anything, and an unmaintained label does not stay
  silent — it starts lying. Dependabot's rewriting of it is **inconsistent**, not
  merely incomplete: measured 2026-08-20, it rewrote a bare `# v5` to `# v7.0.0`
  in GHA-bench#52 while leaving `# v4` stale on the line above **in the same
  file**, and it left every `# vX.Y.Z (YYYY-MM-DD)` comment untouched in
  skills-evals #38/#39/#40 while moving their SHAs. The result in one repo:
  `actions/checkout` at v7.0.1 labelled `# v4.3.1` in one file and `# v6.0.0` in
  two others. A wrong label is worse than no label, because it is read and
  believed — a reviewer trusts it instead of resolving the SHA, and the
  staleness the comment was supposed to advertise is exactly what it hides. The
  SHA is the truth. When you need the version, resolve it:
  `git ls-remote <url> | grep <sha>`, or read the Dependabot PR title.
- **Wait 7 days after a release before adopting it** — the cooling-off above,
  applied by hand. If the newest release is younger than that, pin the previous
  one.
- **Dereference annotated tags.** `gh api repos/<owner>/<repo>/git/ref/tags/<tag>`
  returning `.object.type == "tag"` gives you the tag object's SHA, not the
  commit's, and pinning that fails at runtime. Follow it with
  `git/tags/<that-sha>`, or ask git directly:
  `git ls-remote <url> 'refs/tags/<tag>^{}'`.
- **The one carve-out: a ref into `cms-platform` — a repo this account owns —
  stays on a tag, in either shape that ref takes.** Both of these are correct as
  written, and neither is a SHA-pinning violation to be "fixed" — a reusable
  **workflow**, `Adam-S-Daniel/cms-platform/.github/workflows/<x>.yml@v0.1.88`,
  and a **composite action** referenced from another repo,
  `Adam-S-Daniel/cms-platform/.github/actions/<x>@v0.1.88`. The tag is the
  platform's release identity: `platform-bump.yml` moves the `uses:@` refs, the
  theme gem, `platform.lock` and every `platform_ref:` input to one release in a
  single PR, and `check-platform-pin-consistency.js` asserts each of those refs
  equals `platform.lock`'s `platform_ref` — a SHA in either shape fails that lint
  and strands the bump. The composite shape used to be the exception to the
  exception, pinned by SHA plus a `# vX.Y.Z` comment; that comment was the only
  thing tying such a pin to `platform_ref`, and with the comment gone the tag is
  what ties it. It stops there — nothing third-party is ever a tag, in either
  shape.
- `./local/path` and `docker://` refs have nothing to pin. Leave them.

`sha_pinning_required: true` enforces the rule at the repo level — set by
`repo-settings`' `fleet.yml` for the fleet and `cms-platform`'s
`repo-settings.yml` for the three sites it manages. It governs **actions**, not
reusable-workflow refs: adamdaniel.ai and jodidaniel.com were already enforcing
it at the 2026-07-13 audit and still call 32 tag-pinned cms-platform reusables
apiece, and four repos on the `fleet.yml` default call one each. That is what
makes the carve-out workable — and what leaves a tag in a *third-party* reusable
ref for review, not the setting, to catch.

## Subagent delegation (model routing)

- Don't write code in the main loop: run the implementation in a subagent on an
  appropriately lower-power model (e.g. the Agent tool's `model` override in
  Claude Code; skip if the harness has no subagent support).
- Route by mechanicalness: smallest model (haiku-class) for exactly-specified
  edits — pin bumps, renames, config/doc tweaks; mid-tier (sonnet-class) for
  normal implementation from a clear spec. Escalate rather than ship a wrong
  diff when the task is genuinely subtle (cross-repo invariants, race
  conditions).
- The main loop keeps root-cause investigation, architectural decisions,
  writing the spec, and review of the subagent's diff before commit.
- Delegated work is done when a **verifier exits 0**, not when the report reads
  as finished. Name the exact command in the spec and require its exit code
  back. A subagent that cannot run it reports BLOCKED; a count that disagrees
  with the spec's stated expectation is a stop-and-report condition, never a
  rounding difference.
- **Prove the verifier can fail before you trust it.** A command exiting 0 is
  evidence only if a broken tree makes it exit non-zero; otherwise it is a green
  light wired to nothing. The trap with teeth: `python3 path/to/test_foo.py` on a
  pytest module with no `if __name__ == "__main__"` block imports the file,
  defines the test functions, and exits 0 having run **zero** assertions. It
  looks exactly like a pass. (Real incident, 2026-08-22: appending
  `def test_x(): assert False` to a 53-test file left `python3
  scripts/test_account_zip_selection.py` at exit 0, while `python3 -m pytest` on
  that same file returned exit 1 and "1 failed, 53 passed". Two delegation briefs
  had been citing the hollow command as the gate.) This is the `${PIPESTATUS[0]}`
  lesson above in a second costume — an exit code that belongs to something other
  than the thing you meant to measure. Name the RUNNER in the spec
  (`python3 -m pytest <paths> -q`), never the file, and require the test COUNT
  back beside the exit code: a count is the cheapest proof that anything ran at
  all.
- **A working subagent OWNS the tree — do not commit or push under it.** While a
  subagent is editing, the branch is its workspace, not yours. Push into it and
  the agent's own next `git commit --amend` — correct from where it stands, since
  it has no way to know the commit went public — rewrites a commit that is now
  published, and the branch diverges. Recovery is not a force-push: reset to the
  published tip, re-apply the delta as working-tree changes, and commit it fresh
  so history stays append-only. A working agent's `git checkout -- <file>` will
  also discard uncommitted edits it did not make, including yours. (Real
  incident, 2026-08-22: a checkpoint push landed mid-flight, the agent amended,
  and unwinding it cost a reset-and-reapply.) Wait for the agent to report, then
  push — a clean `git status` plus a recorded result is the signal, not elapsed
  time. Note that a "you have uncommitted changes, please commit and push" stop
  hook cannot see that a subagent holds the tree, so it will advise exactly this
  mistake; say why you are declining rather than complying by reflex.
- **A subagent that goes quiet is not working — check activity, not the clock.**
  Its transcript file's mtime is the real signal; a run journal only writes on
  start and finish, so silence there is expected and proves nothing. Decide the
  staleness threshold in advance, and write the fallback INTO the check-in: what
  to verify by hand if the agent never reports. An indefinite wait on a dead
  agent is the quiet way a gate stops being a gate. (Real incident, 2026-08-22: a
  verification agent wrote for five minutes, died, and left a run looking
  in-flight for an hour.)
- Don't assume the subagent sees this file: general-purpose and custom
  subagents receive the full memory hierarchy (imports included), but
  Explore/Plan-type agents and SDK harnesses with `settingSources: []` skip
  repo guidance entirely. Restate load-bearing constraints (style, test
  command, invariants) in the delegation prompt, and don't hand
  guidance-sensitive work to agents that won't see it.
- **Any prompt that sends a subagent to live-test states the credential
  boundary** — which `HOME`/profile it may use, what it may read, and that it
  must not copy real credentials anywhere to make the test pass. (Real
  incident: a reviewer live-testing a plugin migration in a scratch `HOME`
  copied the account's real OAuth credentials into it. The test worked; nobody
  had asked, and nothing in the prompt forbade it.)
- Supply a throwaway credential, or scope the test to what runs
  unauthenticated. If it genuinely cannot run without a real one, that is the
  operator's call — not a gap for the subagent to close on its own initiative.
- **A tree you made to break something in can still reach production, and the
  obvious fix is worse than the problem in a worktree.** `cp -a` copies
  `.git/config`, so a scratch copy inherits `origin` — measured, 45 such copies
  in one container, 44 of which were never mutated, and the one that was pushed
  14 commits to a real default branch. But `git remote remove origin` inside a
  `git worktree` strips the PARENT checkout's remote, and `git config --local`
  there rewrites the parent's identity (both measured), and the Agent tool's
  `isolation: 'worktree'` means subagents land in one routinely. Before
  disarming anything, run **`/adam:disarm-inherited-reach`** — it carries the
  standalone-vs-worktree test, the reach paths a remote removal does not close,
  and why no in-code guard can substitute.

## Skills ecosystem

- The canonical skills registry is `github.com/Adam-S-Daniel/agentskills`,
  organized as three bundle plugins — `adam` (general-purpose, cloud-safe;
  default-on), `adam-local` (machine-bound), and `fastmail` — each holding
  `skills/<skill>/` directories.
- In Claude Code with the marketplace installed, invoke a skill as
  `/adam:<skill>` (e.g. `/adam:finding-unknowns`).
- Local machines get the marketplace plus per-agent symlinks via that repo's
  `setup.sh`.
- Cloud/ephemeral sessions still get **no** plugins from repo-declared
  settings — that Claude Code limitation (agentskills' `docs/decisions/0001`)
  is unchanged. What changed is that it now has a fix: a repo carrying its own
  `skills.lock` plus the `skills-bootstrap` SessionStart hook installs the
  bundles that lock names directly into those sessions, verified against a
  pinned commit and per-skill digests. Such a session opens with a `skills:`
  verdict naming what loaded, or why nothing did — read it instead of guessing.
- **Adoption is opt-in and double-keyed, and no longer rare.** Delivery needs
  an allowlist entry in `_agent-guidance`'s `repos.yml` AND a `skills.lock` the
  repo committed itself — the fleet sync never writes one, because the lock is
  where a repo declares which bundles it installs (some federate several
  registries). A repo holds both keys, or is mid-adoption holding one, or is
  deliberately out for a reason — a propagation experiment the bundle would
  contaminate, a dormant repo whose sessions never happen. Which of the three
  fits an unfamiliar repo is not guessable: look for `skills.lock`. Bundles
  cost always-on context in every session that carries them, which is why this
  stays a deliberate per-repo decision and not a fleet default.
- New reusable skills graduate **into** the registry (sensitive ones into
  `agentskills-private`) rather than living on in a consumer repo. A long skill
  splits across files rather than growing into one wall of text.

## Two setup gaps you may close, and must not nag about

Skill delivery needs one thing per surface that no repo can commit for itself.
Both are one-time, both are silent when missing, and both are easy to turn into
noise. So: **detect first, and say nothing at all when the check passes.** A
session that opens by telling the operator to paste a script they pasted last
week has spent their attention and taught them to skim the next one.

Run the check once per session and never again that session. Not as a greeting —
answer whatever you were actually asked first — but do **not** wait for the work
to touch skills either. The gap is invisible precisely in the sessions where
nobody is thinking about skills, so a skills-work trigger mostly guarantees the
operator never hears about it. The conditions below are the anti-nag mechanism,
not the timing: they fire only when the gap is real and unfixed, and condition 3
goes false forever the moment the operator closes it.

**Cloud (claude.ai) — PROMPT, never act.** The setup-script field lives in the
environment settings and is not reachable from inside a session, so the most you
can do is ask. Prompt only when **all four** hold; any one false means stay
quiet.

First resolve the project dir, because **`$CLAUDE_PROJECT_DIR` is unset on this
surface** (measured on `remote_mobile`, 2026-08-25): use it when set, otherwise
the nearest ancestor of the cwd that holds more than one repo checkout — in a
hosted multi-repo session that is the cwd's parent, `/home/user`. Substituting an
empty value silently turns conditions 2 and 3 into probes of `/`, which answers
"not multi-repo" and suppresses the prompt — the exact failure this paragraph
exists to prevent. Call the resolved value `$project` below.

1. the session is hosted — entrypoint is `remote*`/`claude_in_slack`/
   `claude-in-slack`/`claude-in-teams`, **or** `$CLAUDE_CODE_REMOTE_SESSION_ID`
   is set (that `OR` is the whole rule; see agentskills' `multi-repo-delivery.md`);
2. the shape is **multi-repo** — `$project` has no `skills.lock` of its own but
   at least one child directory does. A single-repo session needs nothing: its
   own committed `.claude/settings.json` fires the hook;
3. `$project/.claude/settings.json` does not already register a
   `skills-bootstrap` SessionStart hook — **this is the "already there" test, so
   run it before opening your mouth**;
4. some child actually ships `.claude/hooks/skills-bootstrap.sh`, so there is
   something for the wiring to find.

Then say it once, name the snippet's home (`docs/multi-repo-delivery.md` in
agentskills — do not paraphrase it from memory, the project dir is hardcoded
there for measured reasons), and drop it.

**Durable machine — ACT, then one line.** Here you can just fix it, and should.
`claude plugin marketplace list --json` returns `[]` when nothing is configured
(verified), so presence is unambiguous:

- **absent** → `claude plugin marketplace add Adam-S-Daniel/agentskills`, then
  install the bundles the machine wants (`adam` at minimum).
- **present but behind** → `claude plugin marketplace update agentskills`.
- **present and current** → do nothing and say nothing.

"Behind" is a git question, not a guess: the marketplace is a clone under
`~/.claude/plugins/`. **Find it rather than assuming a path** — this account has
already been bitten once by encoding a clone location as a constant — then
compare `git -C <clone> rev-parse HEAD` against
`git ls-remote https://github.com/Adam-S-Daniel/agentskills refs/heads/main`.
Equal means current. The `--json` output may also carry an updated-at or commit
field; read what your build actually prints rather than trusting a field name
from here.

Two things to say afterwards, because both surprise people: an update changes
what loads **next** session, not this one, and a marketplace refresh moves the
three local bundles' contents but not a federated bundle's — that one comes from
its own registry (agentskills' `README.md`).

Neither check belongs in a repo's own `AGENTS.md`, and neither is a reason to
edit a repo. They are session-environment gaps, and the fix lives outside the
tree in both cases.

## Git practices

- Write concise commit messages that explain *why*, not just *what*.
- One logical change per commit.
- Do not amend published commits or force-push shared branches.
- **Merge with a merge commit — `gh pr merge --merge`.** Squash and rebase are
  disabled on every fleet repo, so `--squash` fails rather than falling back;
  do not try it, and do not offer it as a choice. The exceptions are the three
  cms-platform-managed repos (`cms-platform`, `adamdaniel.ai`,
  `jodidaniel.com`), where squash stays enabled because the Decap publish chain
  arms SQUASH auto-merge on every editorial PR and squash is what collapses an
  editor's many per-save commits into one `publish: <title>` commit. Merge
  commits work there too, so `--merge` is the one form that works everywhere.

  Squash is off elsewhere because it is actively unsafe for a repo that pins
  commits by sha: it collapses a branch into a new commit and strands the
  originals on no branch, so a lockfile naming the pre-merge content commit
  (agentskills' `skills.lock`) ends up pinning something a fresh clone of the
  default branch does not contain. Measured on throwaway clones 2026-08-15 —
  `generate_skills_lock.py --check` then fails with `cannot resolve ref`.
  Settings are enforced as code: `repo-settings`' `fleet.yml` for the fleet,
  `cms-platform`'s `repo-settings.yml` for the three above.

<!-- END MANAGED SECTION -->
## Repo-specific additions

# Agent Instructions

All agent-facing instructions live in this file. `CLAUDE.md` contains only a
reference here. If you are a Claude Code agent, you have already loaded this
via `CLAUDE.md`. Other agents: read this file directly.

## Build and test

```bash
# Run unit tests (REQUIRED before every PR)
pip install pytest  # if not already installed
python3 -m pytest tests/ -v

# Validate imports
python3 -c "from runner import main"
python3 -c "from generate_results import generate_results_md"
python3 -c "from test_quality import compute_structural_metrics"
python3 -c "from llm_providers import get_provider"
python3 -c "from version_docs import build_doc, main"
python3 -c "from combine_results import combine"

# Regenerate all reports
python3 generate_results.py --all

# Run a benchmark (v4, all tasks/modes/models). Standard 4-mode set
# (powershell-tool dropped — see Repository rules). Always pass --effort
# explicitly for effort-capable models. For multi-(model,effort) matrices,
# run sequentially via a wrapper script (see run-fresh-matrix-2026-05-06.sh).
python3 runner.py --tasks 11,12,13,15,16,17,18 --modes default,powershell,bash,typescript-bun --models opus48-1m --effort high

# Watch a run while it is still in progress (read-only live dashboard). Reads
# whatever metrics.json files exist so far; never touches the run. The head-to-head
# is automatic: the strongest model+version in this run vs the strongest in the
# previous report (newest completed run), broken down per scripting language.
# Override the auto-pick with --baseline DIR and/or --pair RUNVAR=BASEVAR.
python3 monitor.py --total 140 --watch 30                 # newest run, refresh 30s

# Build per-CC-version reference docs in each run dir (system prompt +
# tool descriptions + sliced changelog). Idempotent; caches under
# .cache/cc-versions/.
python3 version_docs.py                   # all run dirs
python3 version_docs.py results/<run-dir> # one run

# Evaluate test quality (structural metrics only)
python3 test_quality.py results/2026-04-09_152435

# Evaluate test + deliverable quality with the default panel of judges
# (Haiku 4.5 via claude-cli + Gemini 3.1 Pro via the agy CLI). Each judge
# writes its own cache file: test-quality-{short}.json and
# deliverable-quality-{short}.json. 8-worker thread pool by default;
# bump `--workers` if your CLIs + account limits allow more concurrency.
python3 test_quality.py --llm-judge --deliverable-judge \
    --judges haiku45,gemini31pro --workers 8 results/2026-04-17_004319

# Re-evaluate with a single judge only (useful for bias cross-checks)
python3 test_quality.py --llm-judge --judges haiku45 results/2026-04-17_004319

# Build custom act container (optional, eliminates pwsh install overhead)
docker build -t act-ubuntu-pwsh:latest -f Dockerfile.act .
```

## Code style

- Python 3.12+. No type stubs or mypy. Use type hints where they aid readability.
- Dollar amounts in results.md: round to nearest penny (`.2f`).
- Durations in results.md: always in minutes with 1 decimal (`{seconds/60:.1f}min`).
- No emojis in code or docs unless the user asks.

## Terminology

When the runtime wrapper uses `language_mode` (Python-side variable name), the
*user-facing* axis is called **language**, never "mode". This covers docs,
prompts, report prose, and LLM summaries. The internal field name stays
`language_mode` so existing metrics.json readers don't break; everything else
says "language" (e.g. "default/Python, bash, powershell, typescript-bun").
Historical runs also carry a `powershell-tool` language, but reports collapse
it into `powershell` at display time (`_disp_mode`, #30) — the raw
`language_mode` and on-disk `powershell-tool-*` cell dirs are preserved.
Rationale: "mode" is ambiguous with agent-approval-modes and execution modes;
"language" is the concept readers expect.

## Repository rules

- **No agent-generated `.github/workflows/` at repo root.** Agent workflows only exist inside workspaces under `workspaces/`. The repo's own CI workflow (`.github/workflows/ci.yml`) is the exception.
- **Never fix agent-generated code.** The benchmark measures autonomous output. Do not manually fix, edit, or patch workflow files in `workspaces/` or `results/*/generated-code/`.
- **`runner.py` observes and records, never intervenes** on agent code or errors.
- **Workspaces are throwaway.** Don't commit `workspaces/` contents.
- **`results/` is committed.** It contains archived metrics, generated code, and transcripts.
- **`CLAUDE.md` is only a pointer.** All instructions go in `AGENTS.md`. Never put substantive content in `CLAUDE.md` — it should only reference this file.
- **Always set effort AND context explicitly on every run.** Pass `--effort` for every effort-capable model (i.e. everything but Haiku 4.5) and select an explicit context variant (`opus47-1m` vs `opus47-200k`, etc.). Never rely on the CLI defaults: the default effort is version-dependent (it flipped `medium`→`high` at CC 2.1.117) AND is not recorded in `metrics.json`, so cells run without `--effort` cannot be labeled with certainty afterwards. `runner.py` logs a prominent WARNING (not a refusal) when `--effort` is unset for an effort-capable model.
  - **We are NOT studying "default/no-effort" behavior as a condition.** We don't care about "what do you get when you don't specify effort." A run that omitted `--effort` is labeled purely by the effort it *actually* used (derived from the CC-version default) — e.g. the historical no-`--effort` base Sonnet 5 run is `sonnet5-1m-high` because it ran at the CC default `high`, and it is treated identically to an explicit-`high` run. Do NOT add a `default`/`no-effort` label, an inline "derived" marker, or otherwise try to keep no-effort runs distinct; and do not spin up new no-effort runs to characterize default behavior. (The derived-effort inference itself is documented in each combined report's "Model label conventions" section.)
- **Standard language set is `default,powershell,bash,typescript-bun` (4 modes).** Drop `powershell-tool`: under WSL it is functionally identical to `powershell` (same prompt body, same pwsh), so it adds a redundant cell per task without a distinct signal.
- **Post a live status heartbeat during runs.** Roughly every 30 minutes while a run is in flight, relay the full `python3 monitor.py --total <N>` report (run-health + structural metrics + head-to-head) so progress, pace/ETA, and any emerging failures are visible without waiting for completion.

## Never run the benchmark from an ephemeral session in this repo

This repo carries a `skills.lock`, so the fleet's `skills-bootstrap`
SessionStart hook installs the `adam` skill bundle into `$HOME/.claude/skills`
at the start of every **ephemeral** session opened here (cloud/web session, CI
runner, container). `runner.py` builds each cell's environment with
`env = os.environ.copy()` and never overrides `HOME`, so a benchmark cell reads
that same `$HOME/.claude/skills`. Anything the hook installed is therefore
visible to the agent under measurement.

That is fine today and is not a reason to drop the lock: benchmark runs happen
on `ZENDA`, a durable machine, where the hook's surface guard makes it a no-op
(`skills: skipped — durable session`) and nothing is installed. The hazard is
specific and future-dated:

- **Do not launch `runner.py` from a Claude Code cloud/web session, a GitHub
  Actions runner, or any container whose session started in this repo.** The
  hook will have fired first, and every cell in that run sees 8 skills that
  cells in every archived run did not. The benchmark's whole value is
  cross-run comparability (`combine_results.py` pools four campaigns), and an
  uncontrolled skill set in `$HOME` is a silent between-run variable that no
  `metrics.json` field records.
- **This is the open design question in PR #44** ("Run the benchmark on Claude
  Code on the web"), whose `cell_env()` already scrubs the launching session's
  Claude environment — nested-session markers, `CLAUDE_CODE_SESSION_ID`,
  effort variables — precisely because inheriting them changes what the agent
  under test can do. `$HOME/.claude/skills` is the same class of leak and is
  **not** currently scrubbed. If that PR proceeds, either point cells at an
  isolated `HOME` or record the ambient `~/.claude/skills` listing into
  `metrics.json` so a contaminated cell is identifiable after the fact. Do not
  merge a cloud-run mode that leaves it unaddressed and unrecorded.

The reason the lock stays anyway: the repo is also where ordinary maintenance
sessions live — reports, judges, docs, CI — and those are the sessions the
bundle exists to help. The instrument is protected by not running it from an
ephemeral session, which was already true for other reasons.

## Architecture

Key files, trap-detector patterns, and LLM-vs-structural discrepancy handling
→ [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). Combined-report layout
invariants, judge auditing, and reporting internals →
[`docs/REPORTING.md`](docs/REPORTING.md). Read the relevant doc before
touching `runner.py`, `generate_results.py`, `combine_results.py`,
`test_quality.py`, `judge_audit.py`, or `judge_consistency_report.py`.

### Key files

The purpose of every top-level file (`models.py`, `runner.py`,
`generate_results.py`, `combine_results.py`, `recover_cost.py`, `monitor.py`,
`test_quality.py`, `llm_providers.py`, `version_docs.py`, the
`run-opus48-*`/`run-fresh-matrix-*` wrapper scripts, `skills/`) → read
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) before touching any of them.

### Adding new trap detectors

What a new trap detector needs (kebab-case name, detection logic, time
estimate, mode entry) → read [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
before adding one.

### LLM vs structural discrepancy checks

How `counter-gap` vs `qualitative` discrepancies are classified and which one
requires a fix before merging → read
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) after every
`generate_results.py --all` run.

### Combined-report invariants (`combine_results.py`)

The layout invariants `tests/test_combine_results.py` guards (no duplicate
rows, the CLI Version Legend schema, section order, the quality-score lookup
key) → read [`docs/REPORTING.md`](docs/REPORTING.md) before changing
`combine_results.py`.

### The Conclusions prose is disabled for every caller

No report emits `## Conclusions` — the merged max-effort Opus call was dropped
in 2026-04 and `generate_conclusions_from_inputs` discards `speed_cost_input`.
Dead scaffolding survives in both generators → read
[`docs/REPORTING.md`](docs/REPORTING.md) before trying to re-enable it from a
call site.

### Judge rationale audit (`judge_audit.py`)

The drop rule for judges that span ≥ 4 points and how `judge-audit-<kind>.json`
verdicts feed back into `test_quality.load_panel_scores` → read
[`docs/REPORTING.md`](docs/REPORTING.md) before touching `judge_audit.py`.

### Per-judge prompt addendums

How `prompt_addendum_tests` scopes a judge-specific rubric steer, and how to
refresh a single judge's cache with `--rejudge` → read
[`docs/REPORTING.md`](docs/REPORTING.md) before editing `JUDGES[...]` in
`test_quality.py`.

### Combined-report parity with per-run reports

Which per-run `results.md` sections the combined report has and hasn't yet
ported, and the DRY rule for porting the rest → read
[`docs/REPORTING.md`](docs/REPORTING.md) before adding a new per-run section.

### Judge consistency summary (prompt hygiene)

The prompt-hygiene rules for `JUDGE_CONSISTENCY_SUMMARY_SYSTEM_PROMPT` (no
unexplained shorthand, plain-language gap sizes, citation format) → read
[`docs/REPORTING.md`](docs/REPORTING.md) before editing
`judge_consistency_report.py` or its prompts.

### Updating model pricing

Where to edit and check pricing → read [`docs/REPORTING.md`](docs/REPORTING.md).

### Regenerating reports

After changing `generate_results.py`, run:
```bash
python3 generate_results.py --all
```
This regenerates `results.md` for every run directory and updates `README.md`.

### Adding LLM providers

The LLM-as-judge evaluation in `test_quality.py` uses a pluggable provider
system defined in `llm_providers.py`. The benchmark runner (`runner.py`) is
inherently tied to the Claude Code CLI (it tests CLI-specific features), but
the evaluation layer is provider-agnostic.

To add a new provider (e.g., Anthropic API, OpenAI, Codex CLI):

1. Open `llm_providers.py` and create a class inheriting from `LLMProvider`.
2. Implement `is_available()` — return True when the provider can be used.
3. Implement `judge(system_prompt, user_message, model)` — return
   `{"text": str, "cost_usd": float, "input_tokens": int, "output_tokens": int}`.
4. Register it in the `PROVIDERS` dict at the bottom of the file.
5. Use it: `python3 test_quality.py --llm-judge --provider your-provider`.

See the docstring in `llm_providers.py` for a complete example skeleton.

## Before every PR

1. **Run all unit tests and verify they pass:**
   ```bash
   python3 -m pytest tests/ -v
   ```
   All tests must pass. Do not create or update a PR with failing tests.
2. **If you added or changed code, add or update unit tests** in `tests/`.
   New functions need test coverage. Changed behavior needs updated assertions.
3. Run `python3 generate_results.py --all` and verify no errors.
4. **Check for counter-gap discrepancies** in the generated `results.md` files.
   If any "Probable counter gaps" appear, fix them in `test_quality.py` before
   merging (see "LLM vs structural discrepancy checks" above). Qualitative
   disagreements are expected — verify the LLM justification is coherent.
5. Verify all import paths work: `python3 -c "from runner import main"`.
6. Spot-check a few numbers in results.md against raw metrics.json.
7. If you changed architecture or findings, update this file (`AGENTS.md`).
8. If you added files or moved things, update the Files table in `README.md`.

## Current state (2026-06-28)

### opus-4.8 (1M) campaign — COMPLETE; canonical dataset (2026-06)

`results/2026-06-26_103905/` is the **canonical current dataset**: a complete v4
campaign adding `claude-opus-4-8[1m]` (model short `opus48-1m`) at four effort
levels — medium, high, xhigh, and the new **`ultracode`** (xhigh +
dynamic-workflow orchestration; enabled via `CLAUDE_CODE_EFFORT_LEVEL=ultracode`,
since `--effort` does not accept it) — over the same 7 tasks × 5 languages = **140
cells** (136 successful; the 4 failures are xhigh PowerShell-family 30-min
timeouts: 12/powershell-tool, 13/powershell, 16/powershell-tool,
17/powershell-tool). CC versions: 2.1.193 (23 medium cells) + 2.1.195 (117).
Rate-limit clean (0 overloaded/rate-limit/529 markers). ~$578 cells + $17.25 panel
eval (Haiku via Claude CLI; Gemini 3.1 Pro (High) via `agy` = $0 on subscription).
Standard panel-of-judges scores populated; `results/CELLS-COMPLETE.md` marks
collection done. The cross-run report
`results/results_2026-06-26_103905__2026-05-06_173435__2026-04-17_004319__2026-04-09_152435.md`
pools opus-4.8 with the three prior runs and is the headline comparison artifact.
Note: opus-4.8 sometimes picks JavaScript / PowerShell for the free-choice
(default) language, not always Python.

Headline findings (vs opus-4.7 1m, matched task+language): opus-4.8 is the
strongest generation on both quality axes (opus48-1m-ultracode tops Tests
Quality). It is +60–67% time / +64% cost at medium, compressing to ~+15% at high;
writes more and denser tests; the 4 xhigh failures are PowerShell-family timeouts.
**Trap caveat (see `results/analysis/opus48-trap-investigation_2026-06-28.md`):**
opus-4.8 logs ~2× the traps of 4.7, but a hand-review of all 201 occurrences found
this is ~99% benign (99% no circling, 86% legitimate iteration tripping count-based
detectors, ~1% genuine distress) — dominated by a `cd`-prefix dedup measurement
artifact + finer TDD, with a partial CC-version (2.1.131/132 vs 2.1.195) confounder.
Read "~2× traps" as "iterates more granularly," not "fails more often." Follow-up
work tracked in GH issues #21–#27.

### v4 full-matrix benchmark — complete (now a baseline within the combined report)

`results/2026-05-06_173435/`: 280/280 runs across 7 tasks × 5 modes × 8
model-effort combos, $493.46 + $40.57 panel eval = $534.03, 38h 35m wall, 278/280
successful (2 failures). Single-directory, single-CC-version-line (2.1.131 →
2.1.132 mid-run). It was the canonical dataset through 2026-06; it is now pooled
as the **opus-4.7 baseline** inside the opus-4.8 combined report above. Standard
panel-of-judges scores populated.

The 8 model-effort combos: `haiku45` (no effort), `opus`/`sonnet` (no
effort), `opus47-1m` at high/medium/xhigh, `opus47-200k` at medium,
`sonnet46-1m` at medium. The 5 language modes: `default`, `bash`,
`powershell`, `powershell-tool`, `typescript-bun`. The 7 tasks: 11, 12,
13, 15, 16, 17, 18 (task 14 archived earlier).

### Key findings vs prior baselines (CC 2.1.114 → 2.1.131/132)

- haiku45 ~21% faster on average (driven by a bash-mode regression-fix
  on the haiku endpoint; bash specifically went 7× faster, while
  powershell got 33% slower).
- opus47-1m-high notably slower and pricier (+21% dur, +28% cost).
  opus47-1m-medium ~24% faster, opus47-1m-xhigh flat. Other variants
  within run-to-run noise.
- The earlier `2026-04-24_202012` partial run was abandoned (had
  widespread CLI-error failures on haiku/sonnet/opus variants — 46%
  failure rate). Stash dropped on 2026-05-08.

### Earlier reference runs

- `results/2026-04-17_004319/` — 245 runs, mix of `2.1.112` + `2.1.114`. Used as the haiku45 / opus47-1m / sonnet46-1m baseline.
- `results/2026-04-09_152435/` — 64/64, CC 2.1.97/98/100. Used as the no-effort opus / sonnet baseline.
- `results/2026-04-08_192624/` — v3, 64 runs, 1 timeout, 3 double-result bugs. Avg 11.4min/run.
- `results/2026-04-07_225702/` — v2, 111/144 runs. 18 tasks, modes: default/powershell/powershell-strict/csharp-script. Superseded by v3.
- `results/2026-04-02_163146/` — v1, 144 runs, same as v2. Had permission-denial artifacts (88% of errors).
- See `design-and-planning-artifacts/` for historical analysis and planning docs.

### Per-CC-version reference docs

Each run dir contains one `claude-code-<version>.md` per CC version
observed in its `metrics.json` files. Built by `version_docs.py` from
`Piebald-AI/claude-code-system-prompts` (system prompt + tool
descriptions at that tag) and `anthropics/claude-code` `CHANGELOG.md`
(sliced to [lowest CC version observed in any benchmark in this repo,
this version], oldest first). Each `results.md` links these
prominently in the "Claude Code versions used" line at the top.

Regenerate after CC version changes:
```bash
python3 version_docs.py        # idempotent across all run dirs
```

## Deeper references

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — read when touching
  `runner.py`, adding a trap detector, or triaging an LLM-vs-structural
  discrepancy in a generated `results.md`.
- [`docs/REPORTING.md`](docs/REPORTING.md) — read when changing
  `combine_results.py`, `judge_audit.py`, `judge_consistency_report.py`,
  or the per-judge prompt addendums, or when porting a per-run report
  section into the combined report.
