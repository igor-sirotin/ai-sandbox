# Coding agent sandbox

Isolated Linux VMs for running coding agents — [Claude Code](https://claude.com/claude-code),
[OpenCode](https://opencode.ai) — with their permission prompts turned off,
**one VM per project**. Each project has its own GitHub identities, tokens, and
signing key. Built on [Lima](https://lima-vm.io) (Apple Virtualization.framework):
each sandbox is a real, persistent, *mutable* VM — install whatever you want and
it sticks. Networking survives VPNs.

Agents share a project's VM, workspace, git identity and signing key — the VM is a
*project* boundary, not a per-agent one.

## Quick start

```sh
sandbox new           # interactive: asks for a project name, GitHub user/email/token,
                      # default agent, builds the VM, sets up GPG commit signing
sandbox acme          # start the VM and open the project's default agent
sandbox acme opencode    # ...or a specific one
```

`sandbox new` walks you through everything and writes `projects/acme.conf` for
you. The rest is day-to-day use.

## Commands

```sh
sandbox new                    # guided setup (name, identities, tokens, agent, VM, keys)
sandbox ls                     # list all sandbox VMs
sandbox agents                 # list the agents this launcher knows about
sandbox secret set <name>      # store/replace a token in the macOS Keychain
sandbox secret rm  <name>      # remove a stored token
sandbox <project>              # start (if needed) and open the default agent
sandbox <project> <agent>      # open a specific agent (claude, opencode, ...)
sandbox <project> agent        # list agents + whether they're installed in this VM
sandbox <project> agent install <name>   # install an agent into the VM
sandbox <project> agent default <name>   # set the project's default agent
sandbox <project> agent run <name> [args...]  # run an agent explicitly
sandbox <project> shell        # interactive shell in the VM
sandbox <project> code [path]  # open VS Code (Remote-SSH) in the VM
sandbox <project> up           # create/start the VM (auto-applies identities)
sandbox <project> auth         # re-apply identities/tokens (after edits/rotation)
sandbox <project> keys         # (re)create GPG signing key, add to GitHub, verify
sandbox <project> set-email <email>  # change the git email (regenerates the GPG key)
sandbox <project> config [--edit]    # show (or edit) the project's config file
sandbox <project> audit              # report which GitHub credential the VM holds
sandbox <project> exec 'go test ./...'
sandbox <project> status       # VM status
sandbox <project> stop         # stop (disk kept)
sandbox <project> destroy      # delete the VM and everything in it
```

`<project>` maps to an isolated Lima VM `claude-<project>`. Only **known**
projects (one with a config, or an existing VM) are accepted — an unrecognised
name is an error listing the known projects, so a typo can't silently provision
a whole new VM. Use `sandbox new <project>` to create one.
(`sandbox` = `~/ai-sandbox/sandbox`, symlinked into `~/.local/bin`.)

## Agents

Each agent is one file in [`agents/`](agents/) — `agents/<name>.conf` — declaring
how to install and launch it:

```sh
# agents/opencode.conf
agent_desc    'OpenCode (open source, multi-provider)'
agent_bin     opencode
agent_path    '$HOME/.opencode/bin'
agent_install 'curl -fsSL https://opencode.ai/install | bash'
agent_launch  'exec opencode "$@"'
```

**Adding an agent is a new file — nothing else changes.** Values run *inside* the
VM, so keep `$HOME` single-quoted; it's expanded by the VM's shell.

Agents are installed **into the VM on first use**, not by the Lima template. That
means VMs you created months ago pick up newly added agents too — a template edit
would only ever reach *new* VMs. The first launch of an agent takes an extra
~20-30s to download it; after that it's instant, and each agent self-updates from
`$HOME` inside its VM.

Set the agent a bare `sandbox <project>` opens with `use_agent` in the project
config (or `sandbox <project> agent default <name>`); absent, it's `claude`.

Arguments pass straight through — `sandbox acme opencode run "..."`,
`sandbox acme claude --resume`.

> Built-in commands are matched before agent names, so an agent can never shadow
> `shell`, `status`, etc. If one is named after a command, reach it with
> `sandbox <project> agent run <name>`; `sandbox agents` flags the clash.

### Permissions

Both agents are launched with approval prompts off — that's the point of the VM.
Claude Code gets `--dangerously-skip-permissions`; OpenCode's TUI has no such flag,
so first install writes `"permission": "allow"` into
`~/.config/opencode/opencode.json` (only if absent, so edits inside the VM stick).

### Agent credentials

Nothing to configure: log in inside the VM the first time (`/login` for Claude,
`/connect` for OpenCode) and it persists, because the VM is mutable. Claude keeps
this in `~/.claude`, OpenCode in `~/.local/share/opencode/auth.json`. These are
per-VM, so projects don't share agent credentials any more than they share tokens.

> Browser-based sign-in in a headless VM prints a URL — open it on the host and
> paste the code back. API-key auth avoids the round trip.

## Per-project GitHub identities

`sandbox new` generates `projects/<project>.conf` (git-ignored). It's a small
list of `add_identity` calls — see [`projects/example.conf.sample`](projects/example.conf.sample):

```sh
add_identity \
  --github-username my-user \
  --git-name        "My Name" \
  --git-email       me@example.com \
  --token-keychain  acme-my-user

# optional: a second account, used only for repos under one org
add_identity \
  --github-username my-bot \
  --token-keychain  acme-my-bot \
  --org-scope       github.com/some-org
```

- The **first identity is primary**: default git commit identity, active `gh`
  account, and owner of the VM's GPG signing key.
- Extra identities with `--org-scope <host>/<org>` route those orgs to a
  **different token** (longest `host/org` prefix wins; everything else uses the
  primary). Routing is a small git credential helper, with `gh` as fallback. The
  helper only answers `https://` requests, so a token is never handed to a
  cleartext remote. **Routing is convenience, not containment**: every identity's
  token is present in the VM and readable by anything running there — scope your
  PATs, don't rely on the routing to separate them.
- **Tokens are Keychain-only**: `--token-keychain <name>` references an item you
  store with `sandbox secret set <name>` (the wizard does this). Tokens are read
  on the host and piped into the VM over SSH — never written to the repo, and
  never passed as command-line arguments (`security` prompts for them, so they
  don't show up in `ps`).
- `sandbox <project> auth` re-applies after editing a config or rotating a token.
  It **wipes the VM's existing `gh` login and credential file first**, so an
  identity you removed from the config — or a token you rotated — stops working
  inside the VM instead of lingering.
- `projects/*.conf` is **executed as shell code** (it's a tiny shell DSL). The
  launcher refuses to read one that isn't owned by you or that is group/world
  writable; keep them `chmod 600`, as `sandbox new` writes them.

## GPG commit signing

`sandbox new` (and `sandbox <project> keys`) set up, per VM, a passphraseless
**GPG key** for the primary account's **commit signing** — every commit and tag
is signed automatically (`commit.gpgsign true`, `gpg.format openpgp`).

If your token carries the "GPG keys" permission, the key is uploaded to GitHub
automatically; the launcher then makes a signed test commit and confirms, via the
same token, that the key is registered on your account. Otherwise it prints the
ASCII-armored key with the URL to add it manually. Keys are per-project and
independently revocable.

The key **expires after a year**, deliberately. It has no passphrase (commits must
sign unattended) and it lives in a VM whose agent runs with
`--dangerously-skip-permissions`, so assume it can be copied out: the expiry caps
how long a stolen key could keep producing *Verified* commits in your name.
Re-running `sandbox <project> keys` renews the existing key in place — it doesn't
pile up new ones — and prints the expiry date. Renewal also *replaces* the copy
stored on GitHub: GitHub matches keys by fingerprint and silently keeps the old
expiry if you just re-upload, so the launcher deletes the stored key and adds the
renewed one. That's safe for history — per GitHub's docs, commits already
verified stay verified after a public key is removed — but it does need a token
with **GPG keys** write permission; without one you're told exactly that, and
given the key to paste in manually.

If a VM is ever compromised, revoke the key on GitHub; deleting the VM alone
doesn't invalidate it.

Push/pull uses the fine-grained PAT over HTTPS (via the git credential helper), so
no SSH authentication key is created — nothing about the sandbox grants git access
beyond that project's token.

The primary identity needs a `--git-email` that is **verified on the GitHub
account** for signatures to show as *Verified*.

To change the email later, use `sandbox <project> set-email <email>` — it updates
the project config and re-runs the key setup, which generates a fresh GPG key bound
to the new email and re-points `user.signingkey` at it (so signing keeps working).
Upload the new key (automatic if your token allows, else the printed URL), and make
sure the new email is verified on GitHub for the *Verified* badge.

## Work in the VM from your IDE

Each VM is an SSH host, so any IDE's remote-dev mode can edit, run, and debug the
code **inside** the VM (where all the toolchains are). One-time host setup — make
the VMs visible to `ssh` and your IDE:

```sh
# add to ~/.ssh/config (once):
Include ~/.lima/*/ssh.config
```

That exposes each VM as `lima-claude-<project>`. Then:

- **VS Code / Cursor** — `sandbox <project> code` opens Remote-SSH straight into
  `~/workspace` in the VM. (Or: *Remote-SSH: Connect to Host…* → `lima-claude-<project>`.)
- **JetBrains (GoLand/CLion/…)** — *Remote Development → SSH* → host
  `lima-claude-<project>` → choose the IDE backend → open `~/workspace`.

Running services: when a process listens on a port in the VM, VS Code auto-forwards
it to `localhost`. Otherwise tunnel it yourself — `ssh -L 8080:localhost:8080
lima-claude-<project>` — or add `portForwards` to `lima/claude.yaml`.

> Toolchains live at fixed paths — Go `/usr/local/go`, Nim `/opt/nim`, Rust
> `$HOME/.cargo` — in case an IDE's SDK auto-detect needs them pointed out.

## Moving files in and out

There are no host mounts. Each VM is an SSH host (see the IDE section above for the
one-time `~/.ssh/config` include), so use the tools you already have:

```sh
scp lima-claude-acme:workspace/out/report.md .       # pull a file
scp notes.md lima-claude-acme:workspace/             # push a file
rsync -av lima-claude-acme:workspace/out/ ./out/     # pull a tree
```

For code, prefer `git` — that's what the per-project identity and signing key are
for. For editing, point your IDE at the VM over Remote-SSH rather than copying
files back and forth.

This is deliberate. Earlier versions had `mount` (Mutagen sync) and `obsidian`
(live virtiofs mount) subcommands; they were removed. A writable host directory is
the one thing that turns a compromised agent — which runs with
`--dangerously-skip-permissions` — into a compromised host, and no amount of
path vetting makes that a boundary worth maintaining. Pulling files over SSH when
you need them keeps the VM one-directional and the launcher small.

## Toolchains (baked in by provisioning)

| Tool | Location | Notes |
|------|----------|-------|
| Go   | `/usr/local/go`, pinned version | `GOPATH=$HOME/go` |
| Rust | `$HOME/.cargo` | `cargo install` works without sudo |
| Nim + Nimble | `/opt/nim`, built from source | pkgs in `$HOME/.nimble` |
| Nix  | multi-user, flakes on | systemd-managed daemon |
| Node 22, gh, ripgrep, build-essential, … | apt | truecolor enabled |

Coding agents are **not** in this table — they're installed per-VM on first use
from [`agents/`](agents/), so they reach existing VMs too.

Provisioning is **pinned and verified**: Go, Nim and `rustup-init` are downloaded
at an exact version and checked against a SHA-256 recorded in `lima/claude.yaml`;
`gh` and Node come from signed apt repos (no `curl | bash` of a setup script);
the Nix installer is pinned to a release tag. Version bumps are a deliberate edit
— the header comment in `lima/claude.yaml` lists where each published checksum
comes from.

The VM is mutable — `apt install` / `nix profile install` anything ad-hoc and it
persists. Edit `lima/claude.yaml` to change the baseline for *future* VMs.

## Keeping a VM's GitHub access narrow

A VM should hold a **fine-grained PAT** (bound to one owner, explicit repos and
permissions) — never an OAuth token (`gh auth login` via browser), which carries
your whole account.

```sh
sandbox <project> audit    # what credential does this VM actually hold?
```

It reports each configured Keychain token's kind (`fine-grained` / `classic` /
`oauth`, flagged `[WIDE]` if broader than fine-grained) and, for a running VM,
the live `gh` token, its OAuth scopes, git identity and credential routing.
`sandbox <project> auth` prints the same warning when it injects a wide token.

Token prefixes: `github_pat_` fine-grained · `ghp_` classic (account-wide,
scope-based) · `gho_`/`ghu_` OAuth (full account).

`auth` also **pins `GH_TOKEN`** to the project's PAT (single-identity projects
only, so multi-account projects stay switchable). The env var outranks whatever
`gh auth login` stores, so an accidental browser login can't take over — gh
refuses it outright:

> The value of the GH_TOKEN environment variable is being used for authentication.

Caveat: the agent has passwordless sudo inside the VM, so this guards against
accidents and drift, not a determined process. The real cap on blast radius is
the token's own permissions — keep the Keychain items fine-grained.

## Isolation & security

The agent inside a VM runs with `--dangerously-skip-permissions`, so treat the VM
as untrusted and the boundary as the thing doing the work.

- Each project is a **separate VM** — a real boundary between projects and their
  secrets. **No host directories are mounted**; the host filesystem
  isn't visible inside. Move code via `git`. Host SSH keys aren't trusted into the
  VM. **Nothing** is shared back the other way: there are no host mounts at all,
  so a compromised agent has no path to your files. Move things over SSH.
- **This is a filesystem boundary, not a network one.** The VM has unrestricted
  egress: the internet, your LAN, anything your **VPN** routes (that's the flip
  side of "networking survives VPNs" — corporate internal services are reachable
  from inside), and the host itself via `host.lima.internal`. Lima also forwards
  ports the guest binds onto the host's loopback. If you need the agent kept off
  a network, this tool doesn't do that — put the VM behind a firewall you control.
- **Tokens** sit in the macOS **Keychain** on the host and are injected into the
  VM at auth time; they are never passed as command-line arguments. Note that the
  Keychain protects them from *other users and from theft of a powered-off Mac* —
  not from you: any process running as your user can call `security` and read
  them back without a prompt, the same as it could read `~/.lima`.
- **Secrets inside the VM are plaintext-at-rest** in the VM disk image at
  `~/.lima/claude-<project>/` — the `gh` token (`~/.config/gh`), the git
  credentials file, the GPG signing key, and each agent's own login
  (`~/.claude`, `~/.local/share/opencode/auth.json`). That disk is protected by:
  - **FileVault** (whole-disk encryption at rest) — safe if the Mac is off/stolen;
  - **unix permissions** (`~/.lima` is `0700`) — other local users can't read it.

  But **anything running as your macOS user (or root) while you're logged in can
  read them** — the VM is not an extra vault beyond your home directory. Use
  **fine-grained, least-privilege PATs** per project (Contents + PRs, plus GPG
  keys if you want signing-key auto-upload) so a leak is contained and
  individually revocable.
- Resources capped per VM (4 CPUs / 8 GiB / 60 GiB — edit `lima/claude.yaml`).
  Stop idle VMs.

If a VM is compromised, the blast radius is: that project's PATs (revoke them),
its GPG signing key (revoke it on GitHub — it outlives the VM), and anything
reachable from your network. Destroying the VM does not cover the first two.

## Requirements

Lima (`brew install lima`). VMs live in `~/.lima/claude-<project>/`. To spin up
new projects faster you can provision one VM and `limactl clone` it.
