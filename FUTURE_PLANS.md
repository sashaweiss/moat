# Future plans for `moat`

- Add support for adding multiple directories to a session, dynamically or on session start.
    - `--add-workspace`

- Add support to `MoatKit` and the clients for "first-time setup", which installs backing tools like `container` (or other VM backends) and git, and builds the VM image.

- Support Linux: add a concrete implementation to MoatKit backed by `docker` rather than `container`.
    - This requires `MoatKit` and `MoatCLI` to use only cross-platform Swift.
