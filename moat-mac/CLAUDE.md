# Instructions for Claude

See `README.md` for details about the project overall, then read the rest of this file for agent-specific details.

## Requirements

`moat-mac` is a security-minded sandboxing tool for agents running in macOS VMs. Consequently, any design decision must be defensive against misbehaving VM-bound agents.

- The only interface between the host and the VM must be the mailbox directory.
- The host must *only* ingest validated, plain-text `git format-patch` files from the mailbox. No binary, malformed, or otherwise risky files are allowed. Be strict about this: well-behaving agents don't need to give us back anything other than these patches.

## Development philosophy

`moat-mac` is a wrapper around existing tools (`tart`, `git`), with the goal of an ergonomic experience interacting with agents in VMs. To that end:

- The best way to keep `moat-mac` ergnomic and safe is to reduce complexity.
- Only include in the CLI surface exactly the commands and options necessary. Avoid proactively building toggles or options.
- Keep code comments concise, and limit them to referring only to immediately-adjacent code. Long comments are indicative that something has gotten more complex than it should, and we should take a step back to assess holistically.

## Implementation guidelines

- Rather than embedding long chunks of text or JSON into scripts (for example, for seeding files in the VM), store those in the repo as standalone files read in by scripts.

## Tests

See `tests/` and `tests/run.sh` for tests you can run during development that do not require `tart` itself.
