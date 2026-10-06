# Guidelines for `moat`

- By default, any `.git` directory mounted into the VM (directly or transitively via a parent directory) should be mounted as `:ro` unless the user explicitly directs otherwise.
