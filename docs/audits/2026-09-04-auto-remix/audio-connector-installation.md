# Audio connector installation — September 5, 2026

Installed `mixr-audio-understanding@personal`, version 0.1.0, through Codex's plugin installer. Source: `/Users/pranavi/plugins/mixr-audio-understanding`; installed cache: `/Users/pranavi/.codex/plugins/cache/personal/mixr-audio-understanding/0.1.0`. Personal marketplace: `/Users/pranavi/.agents/plugins/marketplace.json`.

The local STDIO MCP uses official MCP 2.1.1 and Google GenAI 2.22.0 SDKs with pinned dependencies. It offers `audio_health` and `critique_transition`. Selected, authorized export excerpts are decoded locally and sent to Google Gemini for timestamped advisory critique. Excerpts are limited to 60 seconds and known export folders. There is no microphone or system-speaker capture. The provider model is configurable; the current default is the documented `gemini-3.8-flash`.

Verification completed:

- Eight local tests passed: bounded decoding, invalid ranges, path/symlink escape, missing credentials, upload authorization, timestamp validation, redacted provider failures, and advisory-only results. Tests were initially run before the implementation and failed because the implementation was absent.
- The official MCP client initialized the server, listed both tools and called `audio_health` successfully, including from the permanent installation.
- Codex plugin manifest and both new/revised skills passed their supplied validators.
- Codex's install command returned plugin ID, version and installed cache path successfully.

## September 8 connection and calibration

The saved credential is accessible. A minimal Gemini request returned OK, and two authorized 26-second audio critiques completed through the installed MCP. The key was not displayed or stored in the repository.

Calibration failed: the second excerpt contained a locally verified 370.5 ms complete dropout at 8.081–8.452 seconds. The blinded model described the passage as intentional subtraction and reported no unintentional dropout. Its observations remain advisory and cannot approve transitions. No further broad cloud listening matrix is justified by this result; preserve the user's free-tier allowance.

Evidence: [baseline critique](implementation/baseline-gemini-2026-09-08.json), [injected-control critique](implementation/control-gemini-2026-09-08.json). Headphone/speaker audition and comparison against human ratings remain outstanding. The connector does not capture speakers.
