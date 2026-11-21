# Temp compatibility

- `contain-writes-soft` should support local-model runtimes that write to `/tmp` instead of honoring `TMPDIR`.
- macOS: extend the soft policy to allow `/private/tmp` (the target of `/tmp`) as well as scratch and native Darwin user temp.
- Linux: whenever scratch TMP is writable, bind it over `/tmp` inside Bubblewrap. This supports hard-coded `/tmp` paths without exposing host `/tmp`.
- Keep the policy behavior and docs aligned across platforms; test that stricter write policies still revoke writes.
