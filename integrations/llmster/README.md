<!--
AI-NOTICE:Schema-Version=0.1
AI-NOTICE:License=MIT
AI-NOTICE:Project=llama.cpp-pi0n00r
AI-NOTICE:Repository=https://github.com/pi0n00r/llama.cpp
-->

# LM Studio llmster integration

Windows llmster backend builds should consume this fork as their llama.cpp
source. Do not clone `ggml-org/llama.cpp` and apply the maintenance patches a
second time.

The source policy follows this fork's current `master`. Each build resolves the
branch once, checks out that exact commit, and retains `llama-source.lock` with
the produced backend. This keeps routine builds current while preserving exact
source provenance for a finished artifact.

From PowerShell in the backend build workspace:

```powershell
. C:\path\to\llama.cpp\integrations\llmster\resolve-source.ps1

git clone --filter=blob:none $env:LLAMA_REPO .\llama.cpp
git -C .\llama.cpp checkout --detach $env:LLAMA_VERSION
```

If the backend builder accepts source parameters, pass the same values through
its existing source-fetch boundary instead:

```powershell
$env:LLAMA_REPO
$env:LLAMA_VERSION
```

The build must not fall back to upstream when either resolution or checkout
fails. Include the generated `llama-source.lock` in the build evidence or
artifact manifest.

## Required checks

Before replacing a Windows llmster runtime:

- verify the checkout HEAD equals `LLAMA_VERSION`;
- build the same backend family and architecture as the installed runtime;
- verify the expected DLL and `llm_engine.node` inventory before installation;
- preserve the original runtime as the rollback artifact;
- run model load, generation, concurrent-slot, tool-call, structured-output,
  and full-context checks through llmster; and
- confirm the running backend identity and library hashes after installation.

The stale-slot correction originates in
[ggml-org/llama.cpp#27624](https://github.com/ggml-org/llama.cpp/pull/27624).
It clears prompt, checkpoint, and KV/recurrent state when an LRU-selected slot
has no valid restored state. Its regression matters most under parallel slot
reuse and must be exercised with both disabled and enabled RAM prompt caching.

The gfx1151 correction remains relevant only to affected ROCm builds. If
upstream implements either correction, retain the fork delta until the
equivalent upstream behavior passes the corresponding hardware and runtime
acceptance checks.
