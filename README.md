# moat

Uses Apple's native, open-source [`container`](https://github.com/apple/container) tool to isolate Claude Code in a Linux VM tied to a workspace.

Features:

- Isolated: Claude can't access files outside the project it's working on.
- Performant: `container` is optimized for Apple Silicon.
- Resumable: Claude memory and session state are saved per-workspace.
- Personal: `moat` sessions use your host's Claude settings.

> [!WARNING]
> `container` doesn't support network firewalling, so Claude Code in the VM will have full network access. Take care as to the contents of the directory you give to `moat`.

> [!WARNING]
> Claude Code has passwordless `sudo` inside the container so it can install whatever tools it needs. Note that VM instances are transient (run with `--rm`), so tool installs don't persist across `moat` sessions.

## Installing

Before running `moat` for the first time, you need to install some stuff.

1. Install [`container` from Github Releases](https://github.com/apple/container/releases), using the `.pkg` installer.

1. Install Rosetta. Required because something in the `container build` pipeline requires Rosetta installed, even if you're building for arm64.

```sh
softwareupdate --install-rosetta --agree-to-license
```

1. Run `container system start`. This will prompt you to install a default kernel.

1. Build `moat`'s VM image. From this directory:

```sh
make image
```

> [!NOTE]
> To update `moat`'s version of Claude Code, rebuild the image.

> [!NOTE]
> The default image is `moat:base`. See `images/` for others, and `--image` to use them.

1. Install `moat` itself. Download `moat-<version>-macos-arm64.zip` from [Releases](https://github.com/sashaweiss/moat/releases), unzip it, and add it to your `PATH`.

### Building from source

Alternatively, build `moat` from source. From this directory:

```sh
make
./moat # symlink to the built product
```

### Developing

See `Moat.xcworkspace` to open all the various packages in here at once.

### Releases

For releasing, see `MoatRelease/` and `make release`.

## Usage

```sh
moat <path-to-repo>
```

For full config options, see:

```
moat --help
```

### Shell completions

To generate completions for `moat` for a given shell (such as `zsh`), run:

```sh
moat --generate-completion-script <shell>
```

You can use this to add `moat` completions to your shell by adding the following to your shell config:

```sh
source <(moat --generate-completion-script <shell>)
```
