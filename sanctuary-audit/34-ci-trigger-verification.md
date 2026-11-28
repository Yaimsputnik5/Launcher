# CI trigger verification

Recent source commits were written with the MCP bulk file-push path, which uses
the Git tree/commit API. Those commits changed `ios-build` but produced no
Actions run and no check suite:

- `59fe602fc4a45484ee1f33f8d0e0259a2d917240`
- `8ed3deea6b91155db3dfc7cb4f0f2e29896ebf4d`
- `945aa23672d90ea0dee9db58098b9b85d012921f`
- `ad256f4f64dba98631b01e7e1d8b15e0eb103c86`
- `2c46b519a6a8858b318a3cb291e99d3cb2a921be`

A control commit was then written with the single-file GitHub contents API
(`create_or_update_file`), `cf6c856f43cb90e4ee92ea36d2f98c66e724d017`, and a
follow-up README commit, `853754d8b45b19e8156f9ad50fba43086500be3f`. Neither
produced a check suite either. The workflow at
`.github/workflows/ios-build.yml` is still active and still declares a push
trigger on `ios-build`, so the absence of runs is a repository-side event
delivery issue, not a workflow syntax or `[skip ci]` issue in these commits.

Before this verification, the newest run was `46081101414` for
`c39369d65865feebdbbb60674d208817408495e0`, and the `ios-ipa` release still
contained the stale unsigned IPA with SHA-256
`e5a48f13bab8da1daa4c9a5c26475f57855cd2e49176665cf251baed7ec21307`.
A maintainer must trigger `Build iOS IPA` manually (or restore push-event
delivery) before a fresh IPA exists. The new asset must then be verified by its
head SHA, `unzip -tq`, size, and SHA-256 before asking the user to retest. This
note records the trigger diagnosis only; it does not claim a successful build.

No account credential was provided, requested, captured, or stored.
