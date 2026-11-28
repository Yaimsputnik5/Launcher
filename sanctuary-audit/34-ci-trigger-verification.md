# CI trigger verification

Recent source commits were written with the MCP bulk file-push path, which uses
the Git tree/commit API. Those commits changed `ios-build` but produced no
Actions run and no check suite:

- `59fe602fc4a45484ee1f33f8d0e0259a2d917240`
- `8ed3deea6b91155db3dfc7cb4f0f2e29896ebf4d`
- `945aa23672d90ea0dee9db58098b9b85d012921f`
- `ad256f4f64dba98631b01e7e1d8b15e0eb103c86`
- `2c46b519a6a8858b318a3cb291e99d3cb2a921be`

The workflow at `.github/workflows/ios-build.yml` is active and triggers on
pushes to `ios-build`; this note is intentionally written through the GitHub
contents API (`create_or_update_file`) so the commit emits a normal push event.
Its message does not contain `[skip ci]`.

Before this trigger, the newest run was `46081101414` for
`c39369d65865feebdbbb60674d208817408495e0`, and the `ios-ipa` release still
contained the stale unsigned IPA with SHA-256
`e5a48f13bab8da1daa4c9a5c26475f57855cd2e49176665cf251baed7ec21307`.
A successful new run must be verified by its head SHA, `unzip -tq`, asset size,
and SHA-256 before asking the user to retest. This note records the trigger
mechanism only; it does not itself claim a successful build.

No account credential was provided, requested, captured, or stored.
