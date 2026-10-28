# Future plans for `moat`

- Add support for adding multiple directories to a session, dynamically or on session start.
    - `--add-workspace`

- Add support to `MoatKit` and the clients for "first-time setup", which installs backing tools like `container` (or other VM backends) and git, and builds the VM image.

- Support Linux: add a concrete implementation to MoatKit backed by `docker` rather than `container`.
    - This requires `MoatKit` and `MoatCLI` to use only cross-platform Swift.

- Have moat create a git worktree for the agent to work in, rather than mounting the repo's working tree directly.
    - Mount the worktree read-write, and the main repo's `.git/` separately: read-only by default, or read-write if configured.
    - This avoids nesting a potentially-fragile read-only `.git/` mount inside a read-write workspace mount.
