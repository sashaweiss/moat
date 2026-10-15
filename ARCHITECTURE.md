# `moat`: High-level architecture

> [!NOTE]
> Not everything described here exists yet.

## MoatKit

A Swift Package that owns a long-running connection to a "agent in a VM" session in a subprocess, exposing tools for interacting with and administering the session.

- `class Session`: represents an "agent in a VM" process. Takes an injected `SessionCommands`. 

- `struct SessionCommands`: a collection of commands needed by a `Session`.

- `class SessionManager`: Singleton responsible for sessions.
    - Uses `~/.moat/sessions` as a database of Claude Code state and session metadata.
    - Inspects `~/.moat/sessions` and uses `SessionCommands` to list sessions and their status: stopped, idle, busy, "owned by another process".
        - On launch, all sessions are "stopped" unless they appear in `container list` or equivalent as "running", in which case they are "owned by another process".
        - As sessions start, they become "busy". If the terminal doesn't see activity for 3s, a session becomes "idle".
    - Exposes teardown of all sessions for app exit.

- `~/.moat/sessions`: the sessions database.
    - Stores Claude Code state and JSON metadata for each session.
    - Sessions are keyed by "absolute path of workspace".
    - "Removing" a session removes all state and metadata.

- `class SettingsManager`: Singleton responsible for settings.
    - Reads/writes `~/.moat/settings.json`.
    - Supports rebuilding the `container` or Docker image.
    - Tracks "Claude Code version in the image".

## MoatGUI

A macOS app that uses MoatKit to provide a GUI interface to an agent-in-a-VM session, including: text-based IO; administration actions like starting/stopping the session; a file browser of the directory the session's running in; a diff viewer (powered by git diff) for changed files in the directory.

### Layout

- Sidebar + "main content view". Separate-window `Cmd+,` Settings pane.

- Sidebar: our sessions, as listed by `MoatKit.SessionManager`.
    - Context menu to start or stop an existing session.
    - `+` opens a folder picker, to add new sessions.
    - Selecting (or adding) a session shows a sheet of options, prefilled with our `settings.json` defaults: git access mode, RAM, CPUs, Claude Code mode, etc.

- Main content view: three tabs pertaining to the sidebar-selected session.
    - First, a terminal with the Claude session in the VM
        - Read-only (scrollback available) if stopped.
        - Scrollback is not persisted across app launches.
    - Second, a `git diff` viewer.
    - Third, a file browser.

- Settings pane: interface for `MoatKit.SettingsManager`.

## Future plans

- Add support for adding multiple directories to a session, dynamically or on session start.

- Add a "release" script to archive and notarize `MoatCLI` and `MoatGUI`.

- Add support to `MoatKit` and the clients for "first-time setup", which installs container (or other VM backends) and builds the VM image.

- Support Linux: add a concrete implementation to MoatKit backed by `docker` rather than `container`.
    - This requires `MoatKit` and `MoatCLI` to use only cross-platform Swift.

- Reuse MoatKit to power a browser-based web UI, driven by a Swift HTTP server wrapping MoatKit.
