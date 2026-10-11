# `moat`: High-level architecture

> [!NOTE]
> Not everything described here exists yet.

## MoatKit

A Swift Package that owns a long-running connection to a "agent in a VM" session in a subprocess, exposing tools for interacting with and administering the session.

The primary API is a protocol with a concrete implementation backed by `moat`.

## MoatGUI

A macOS app that uses MoatKit to provide a GUI interface to an agent-in-a-VM session, including: text-based IO; administration actions like starting/stopping the session; a file browser of the directory the session's running in; a diff viewer (powered by git diff) for changed files in the directory.

## Future plans

- Reuse MoatKit to power a browser-based web UI, driven by a Swift HTTP server wrapping MoatKit.

- Reimplement `moat`'s Python functionality in MoatKit, rather than calling `moat` from it. Reduce `moat` to a "MoatCLI" Swift CLI wrapper around MoatKit.

- Support Linux: add a concrete implementation to MoatKit backed by `docker` rather than `container`.
    - This requires `MoatKit` and `MoatCLI` to use only cross-platform Swift.
