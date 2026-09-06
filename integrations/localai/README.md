<!--
AI-NOTICE:Schema-Version=0.1
AI-NOTICE:License=MIT
AI-NOTICE:Project=llama.cpp-pi0n00r
AI-NOTICE:Repository=https://github.com/pi0n00r/llama.cpp
-->

# LocalAI integration

LocalAI should consume this fork as its llama.cpp source. The operator does not
apply the gfx1151 patch separately.

The source policy tracks the current `master` branch. Every build resolves that
branch once to an immutable commit and records the result in `llama-source.lock`.
That gives routine installs current source without making produced artifacts
non-reproducible.

From a LocalAI source tree or builder environment:

```sh
eval "$(/path/to/llama.cpp/integrations/localai/resolve-source.sh)"
make -C backend/cpp/llama-cpp \
  LLAMA_REPO="$LLAMA_REPO" \
  LLAMA_VERSION="$LLAMA_VERSION" \
  BUILD_TYPE=hipblas \
  AMDGPU_TARGETS=gfx1151 \
  llama-cpp-fallback
```

The deployment build must carry the same two values through any recursive make
or container-build boundary. It must also include the generated
`llama-source.lock`
with the release manifest.

## Acceptance

A candidate is not qualified merely because it compiles. Before promotion on
gfx1151 it must pass:

- split-versus-unsplit long-prompt correctness;
- a full-context generation through the resulting worker;
- LocalAI-routed model discovery and generation;
- tool calling and representative structured-output cases;
- authenticated access and IPv4/IPv6 listener checks; and
- readback of the exact running source and library hashes.

If upstream implements an equivalent correction, retain this fork delta until
the upstream implementation passes the same hardware tests. If the patch no
longer applies cleanly during an upstream catch-up, stop the build rather than
silently falling back to upstream host-buffer behavior.
