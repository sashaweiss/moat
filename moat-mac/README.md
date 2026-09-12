# moat-mac

A tool for running agents inside macOS VMs using [`tart`](https://github.com/cirruslabs/tart), sharing output with the host via git patches.

## Overview

Each `moat-mac` "session" is its own VM, cloned from a base VM image. Sessions are intended to be durable, with session state stored only in the VM.

A session is created by `git clone`-ing a repo (from local source) into a fresh VM; the session is named after the repo. Using `git clone` rather than copying ensures that only files tracked by `git` are shared with the VM.

Output from the agent in the VM is shared back to the host via a "mailbox" directory mounted from the host into the VM. Agents place `.patch` files into the mailbox, representing their commits in the VM, such that `moat-mac` can "pull" branches from the VM. See below for details.

> [!IMPORTANT]
> macOS VMs are much heavier-weight than the Linux VMs used by `moat`; they require significant disk space, RAM, and CPU resources from the host to be useful. See below for details.

## Installation

First, ensure `moat-mac` is on your `$PATH`.

> [!TIP]
> Zsh completions for `moat-mac` are shipped in `completions/_moat-mac`; to take advantage, ensure `_moat-mac` is added to your Zsh's `fpath`.

Then, install `tart`, and build the `moat-mac-base` VM image (on which sessions will be based).

```sh
brew install cirruslabs/cli/tart
moat-mac setup   # builds moat-mac-base: Xcode image + Claude Code
```

This `moat-mac-base` image comes preinstalled with Claude, Xcode, Homebrew, and other macOS-y tooling; most provided by `tart`'s `macos-tahoe-xcode` image. See the [image templates here](https://github.com/cirruslabs/macos-image-templates).

> [!IMPORTANT]
> This step involves downloading a ~25 GB macOS image, which when expanded into our base VM will require 80+ GB of disk space.
>
> Session disk-space usage is based on APFS copy-on-write, so session VMs only consume additional disk space for what they contain on top of the base VM image (such as DerivedData, simulators, installed tools, etc). Consequently, while each will require substantial disk space they all share that initial ~80 GB cost.
>
> `tart` caches VM images in `~/.tart`; see its documentation for more.

## Creating a session

To create a session, run:

```sh
moat-mac create [--repo <path>]
```

This:
1. Creates a `moat-mac/main` branch in the given repo, based on `main`.
1. Clones the `moat-mac/main` branch in the given repo to a temp directory, using local source.
1. Tarballs the temp-directory repo clone into the VM's eventual mailbox.
1. Creates a new VM based on `moat-mac-base`, named `moat-mac-<repo>`.
1. Boots the VM and runs `guest/guest-setup.sh` in it to bootstrap the repo, helper scripts, Claude instructions, etc.

### Viewing sessions

To view existing `moat-mac` sessions, run:

```sh
moat-mac list [--json]
```

### Starting or resuming a session

Once a session is created, it can be started by running:

```sh
moat-mac start [--session <name>]
```

> [!NOTE]
> The first time you start a newly-created session you must log in to Claude; `moat-mac` detects this and automatically runs `/login` for you to start the process. The login is thereafter persisted in the VM.

## Sharing files with the VM: the mailbox

Each session gets a "mailbox" directory in `~/.moat-mac/<session>/mailbox`, which is the only piece of shared filesystem between the host and the VM.

Output from agents in the VM should be considered "untrusted". Consequently, `moat-mac` does not support "receiving" arbitrary files from the mailbox; that defeats the point of a sandbox! Output from the VM is limited to `.patch` files containing text, as described below.

> [!WARNING]
> Avoid inspecting or manipulating the mailbox's contents manually, rather than via `moat-mac`.

### Sharing branches with the VM

Git branches are shared with the VM by placing `.patch` files into an organized directory structure in the mailbox, which `moat-mac` reconciles with the host or VM's local branches using the `pull` and `push` commands.

> [!NOTE]
> Branches shared between the host and VM are prefixed with `moat-mac/*`.

To pull `moat-mac/*` branches from the VM to the host, `moat-mac` reads the `.patch` files in the mailbox (placed there by the agent in the VM) and applies them to the host's local `moat-mac/*` branches. To pull, run:

```sh
moat-mac pull [--session <name>]
```

To push `moat-mac/*` branches from the host to the VM, `moat-mac` creates `.patch` files from the commits on the host's local `moat-mac/*` branches and places them in the mailbox. The agent in the VM can then fetch and apply them to its branches. To push, run:

```sh
moat-mac push [--session <name>]
```

### Sharing files into the VM outside of git

`moat-mac` supports copying files into the mailbox to share files one-way with agents in a VM; for example, screenshots or other supporting files while a session is ongoing.

To share files into the VM, run:

```sh
moat-mac share --file <path> [--file <path> ...] [--session <name>]
```

## Other host-side session state

`moat-mac` keeps other session state on the host in `~/.moat-mac/<session>`, such as metadata about the session. Other than the mailbox, none of this is shared with the VM.
