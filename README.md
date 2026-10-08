# moat

Uses Apple's native, open-source [`container`](https://github.com/apple/container) tool to isolate a Claude Code instance to a specific directory.

Features:

- Isolated: Claude can't access files outside the project it's working on.
- Performant: `container` is optimized for Apple Silicon.
- Resumable: `.claude/` directories inside the container are persisted in `$HOME/.moat`, so `moat` sessions can be resumed.
- Shared context: shares your working directory from the host machine to `container` using a volume mount, mirroring changes.
- Shared Claude settings: your `CLAUDE.md` and `settings.json` from `$HOME/.claude` are shared with the VM.
- Persistent credentials: once you log into Claude in `moat`, it stores your credentials in `$HOME/.moat` and shares those credentials across sessions so you stay logged in.

> [!WARNING]
> `container` doesn't support network firewalling, so Claude Code in the VM will have full network access. Take care as to the contents of the directory you give to `moat`.

> [!WARNING]
> Claude Code has passwordless `sudo` inside the container so it can install whatever tools it needs. Note that VM instances are transient (run with `--rm`), so tool installs don't persist across `moat` sessions.

## Installing

Before running `moat` for the first time, you'll need to install some stuff.

1. Install [`container` from Github Releases](https://github.com/apple/container/releases), using the `.pkg` installer.

1. Install Rosetta. Required because something in the `container build` pipeline requires Rosetta installed, even if you're building for arm64.

```sh
softwareupdate --install-rosetta --agree-to-license
```

1. Run `container system start`. This will prompt you to install a default kernel.

1. Build the `moat` container. From this directory:

```sh
container build -t moat:latest
```

> [!NOTE]
> To update `moat`'s version of Claude Code, rebuild the container:
>
> `container build -t moat:latest --no-cache`

## Usage

```sh
moat <path-to-repo> [--permission-mode <mode>] [--model <model>] [--skills <dir>] [--env-file <path>] [claude-args...]
```

- `--permission-mode` passes through a Claude Code permission mode to the `claude` session that runs in `moat`. Defaults to `auto`.

- `--skills` points to a directory containing Claude skills that will be available inside `moat`.

- `--env-file` points to a `KEY=VALUE` file whose contents are injected as environment variables inside the container. Use this to inject secrets to Claude, such as API tokens.

```sh
echo 'MY_TOKEN=lalalala' > "$HOME/.moat/tokens.env"
chmod 600 "$HOME/.moat/tokens.env"
moat <path-to-repo> --env-file "$HOME/.moat/tokens.env"
```

- `--model` sets the Claude model for the session. Defaults to `opus`, which always resolves to the latest Opus-class model.

- Trailing arguments are forwarded to `claude` inside the container.
