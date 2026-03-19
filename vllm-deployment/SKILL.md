---
name: vllm-deployment
description: Guides deploying, configuring, and troubleshooting vLLM OpenAI-compatible
  servers. Use when serving LLMs with vLLM, sizing models for GPU/VRAM constraints,
  writing vllm serve commands, diagnosing OOM or API errors, configuring air-gapped
  deployments, or calling vLLM-specific API extensions like structured outputs and
  reasoning outputs.
---

# vLLM Deployment

Operational guide for deploying vLLM's OpenAI-compatible server (FastAPI). Covers server configuration, model sizing for 64-96GB VRAM, air-gapped operation, API extensions, and troubleshooting.

## Interaction Design

When a user needs help deploying or troubleshooting vLLM, gather these inputs (ask only for what is missing):

1. **vLLM version** -- if unknown, suggest: `vllm --version` or `pip show vllm`
2. **GPU type(s) and VRAM per GPU** -- e.g., 4x T4 (16GB each)
3. **Model name/path** -- HuggingFace ID or local directory
4. **Target context length** -- default model context or a cap
5. **Expected concurrency** -- how many simultaneous requests
6. **Air-gapped?** -- whether the environment has internet access

Then generate a recommended `vllm serve` command with explanations, or a diagnostic plan if an error is provided.

## Version and Upgrade Map

| Feature / Change | Min Version | Symptom if Wrong | Detection | Remediation |
|---|---|---|---|---|
| V1 engine default | v0.8.1 | Behavior differs from older blogs/guides | `VLLM_USE_V1=0` still works | Adapt to V1 defaults; prefix caching is now on by default |
| V0 engine removed | v0.11.0 | `VLLM_USE_V1=0` has no effect or errors | Set env var and observe | Upgrade client expectations to V1; no fallback |
| `guided_*` fields removed | v0.12.0 | 400/422 errors on `guided_json`, `guided_regex`, etc. | Send a `guided_json` request | Replace with `structured_outputs` in `extra_body` |
| CUDA version bump | v0.12.0+ | Driver or CUDA version mismatch errors | `nvidia-smi` vs required CUDA | Upgrade NVIDIA driver or pin older vLLM |
| `reasoning_content` field | <= v0.11.x | Response uses `reasoning_content` for reasoning steps | Check response JSON keys | Upgrade to v0.12.0+ and migrate to `reasoning` |
| `reasoning` field (current) | >= v0.12.0 | Response uses `reasoning`; `reasoning_content` kept for backcompat | Check response JSON keys | Prefer `reasoning`; fall back to `reasoning_content` for older servers |
| `reasoning_content` removed | v0.16.0 | `reasoning_content` field no longer present in responses | Upgrade to v0.16.0+ | Migrate all client code to use `reasoning` before upgrading |
| Offline `/docs` support | v0.14.0+ | `/docs` page blank or fails in air-gapped env | Visit `http://host:port/docs` offline | Add `--enable-offline-docs` to serve command |
| RTX Blackwell (SM120) fixes | v0.15.1 | FP8 kernel errors on Blackwell GPUs | Check GPU arch with `nvidia-smi` | Upgrade to v0.15.1+ |
| PyTorch 2.10 runtime bump | v0.16.0 | Environment dependency breakage | Check PyTorch version | Pin to v0.15.1 or upgrade PyTorch/runtime deps together |

**Current release status (as of Feb 2026):** v0.15.1 is stable. `v0.16.0` is pre-release with breaking changes (`reasoning_content` removed and runtime/dependency bumps).

**Safe minimum version recommendation:** v0.12.0+ for new deployments (V1 engine only, structured outputs current, modern runtime baseline). Use v0.15.1 for production (includes Blackwell fixes and security patches).

Always verify current release status before upgrade planning: `https://github.com/vllm-project/vllm/releases`

## Production Readiness Gates

Before calling a deployment "production ready", require all of the following:

1. Pin exact vLLM/container versions and immutable model snapshots (no floating `latest`).
2. Capture preflight compatibility (`vllm --version`, torch runtime, `nvidia-smi`) and confirm quantization support on the target GPU architecture.
3. Keep security minimums: `--api-key` on every server and avoid `--trust-remote-code` unless explicitly reviewed and mirrored.
4. Enforce deterministic serving contract: explicit model, explicit `--served-model-name`, explicit memory caps (`--max-model-len`, `--max-num-batched-tokens`, `--max-num-seqs`), and `--generation-config vllm`.
5. Roll out with canary + rollback path (previous image and model snapshot ready).

## vllm serve Runbook

### Minimal Working Command

```bash
vllm serve meta-llama/Llama-3.1-8B-Instruct \
  --dtype auto \
  --api-key "${VLLM_API_KEY}"
```

### Memory-Safe Template

```bash
vllm serve <model> \
  --dtype auto \
  --served-model-name <served-model-name> \
  --api-key "${VLLM_API_KEY}" \
  --gpu-memory-utilization 0.85 \
  --max-model-len 4096 \
  --max-num-batched-tokens 2048 \
  --max-num-seqs 8 \
  --generation-config vllm
```

### Air-Gapped Template

```bash
HF_HUB_OFFLINE=1 vllm serve /local/path/to/model \
  --dtype auto \
  --api-key "${VLLM_API_KEY}" \
  --download-dir /local/path/to/model \
  --gpu-memory-utilization 0.85 \
  --max-model-len 4096 \
  --enable-offline-docs
```

### Multi-GPU Templates

```bash
# TP=2 (2x GPUs, e.g., 2x RTX 6000 Ada)
vllm serve <model> --tensor-parallel-size 2 --dtype auto --max-num-seqs 8 --api-key "${VLLM_API_KEY}"

# TP=4 (4x GPUs, e.g., 4x L4 or 4x T4)
vllm serve <model> --tensor-parallel-size 4 --dtype auto --max-num-seqs 8 --api-key "${VLLM_API_KEY}"
```

For T4 GPUs specifically, force `--dtype float16` (BF16 not supported on Turing SM 7.5).

### Flag Glossary

| Intent | Flags | Notes |
|---|---|---|
| **Networking / Auth** | `--host`, `--port`, `--api-key` | `--api-key` sets required Bearer token for all requests |
| **Model Identity / Loading** | `--served-model-name`, `--download-dir`, `--load-format`, `--safetensors-load-strategy` | Use `--served-model-name` to expose a stable API model name independent of filesystem/HF path |
| **Behavior Overrides** | `--generation-config vllm`, `--chat-template`, `--chat-template-content-format` | `--generation-config vllm` prevents model's `generation_config.json` from overriding sampling defaults |
| **Memory Controls** | `--gpu-memory-utilization`, `--max-model-len`, `--max-num-batched-tokens`, `--max-num-seqs`, `--cpu-offload-gb` | `--gpu-memory-utilization` default is 0.9; `--max-num-seqs` is a key concurrency cap |
| **Distributed** | `--tensor-parallel-size`, `--pipeline-parallel-size`, `--distributed-executor-backend` | TP shards weights across GPUs; use `mp` backend for single-node |
| **Reasoning** | `--reasoning-parser`, `--default-chat-template-kwargs` | `--reasoning-parser` selects the parser (e.g., `deepseek_r1`, `granite`). Some models need thinking explicitly enabled/disabled via `--default-chat-template-kwargs '{"thinking": true}'` or `'{"enable_thinking": false}'`. |
| **Offline / Docs** | `--enable-offline-docs`, `--enable-request-id-headers` | `--enable-offline-docs` vendors Swagger UI assets for air-gapped `/docs` |

### Critical Pitfalls

1. **Chat template required.** `/v1/chat/completions` errors if the model lacks a chat template. Fix: `--chat-template <path>`.
2. **Sampling params overridden.** Model's `generation_config.json` can silently override temperature/top_p. Fix: `--generation-config vllm`.
3. **`/docs` needs internet by default.** Swagger UI fetches from CDN. Fix: `--enable-offline-docs`.
4. **Missing model argument.** Use either `vllm serve <model>` (positional) or `vllm serve --model <model>` (flag). Always specify your model explicitly. Newer vLLM may load a default model when omitted, which can mask config mistakes.
5. **Model-name contract mismatch.** Clients send `model="<name>"`; if this doesn't match what the server exposes, requests fail with model-not-found style errors. Set `--served-model-name` intentionally and align clients.
6. **Runtime/driver mismatch.** vLLM binaries are tied to specific PyTorch/CUDA builds. Check `nvidia-smi` and your installed torch/vLLM versions together before upgrading.

## Model Selection for 64-96GB VRAM

### Memory Math

- **Weights**: BF16/FP16 = ~2 bytes/param, FP8 = ~1 byte/param, INT4 = ~0.5 bytes/param
- **KV cache**: grows with `max_model_len` x concurrency x batch size; this is where runtime OOMs come from
- "Loads but OOMs on first request" = weights fit, KV cache allocation does not

### Decision Flow

```
1. What is your total VRAM?
   ├─ <= 16GB (single GPU) → Tier A (7-9B) only
   ├─ 32-48GB → Tier A or B (14-16B)
   ├─ 64GB → Tier A, B, or C (24-27B); Tier E (70B) only with INT4
   └─ 96GB → Tier A-D freely; Tier E (70B) with INT4/FP8

2. What is your GPU architecture?
   ├─ T4 (Turing SM 7.5) → GPTQ/AWQ/INT8 only; no FP8, no Marlin; --dtype float16
   ├─ A100 (Ampere SM 8.0) → GPTQ/AWQ/INT8/Marlin; no FP8
   ├─ L4 (Ada SM 8.9) → All formats including FP8 and Marlin
   └─ H100 (Hopper SM 9.0) / RTX 6000 Ada (SM 8.9) → All formats

3. What context length and concurrency?
   ├─ Low (4k ctx, 1-4 concurrent) → more headroom for larger models
   └─ High (8k+ ctx, 8+ concurrent) → reduce model tier or quantize more aggressively
```

### Model Tier Summary

| Tier | Params | BF16 Weight Size | Best For | Notes |
|---|---|---|---|---|
| A | 7-9B | ~16GB | Single GPU, fast iteration | Llama 3.1 8B, Mistral 7B, Gemma 2 9B, Granite 8B |
| B | 14-16B | ~32GB | Better quality, 1-2 GPUs | Phi-4 14B, Phi-4-reasoning 14B, Ministral 3 14B Instruct |
| C | 24-27B | ~48-54GB | Sweet spot for 2x48GB or 4x24GB | Gemma 2 27B |
| D | 35B | ~70GB | Near-70B quality on 96GB | Command-R 35B; conservative ctx/batching required |
| E | 70B | ~140GB (needs quantization) | Best quality; INT4 required for 96GB | Llama 3.1 70B, RedHatAI Llama 3.1 70B w4a16 GPTQ |

### Quantization Compatibility

| Method | T4 (Turing) | A100 (Ampere) | L4 / RTX 6000 Ada | H100 (Hopper) |
|---|---|---|---|---|
| GPTQ | Yes | Yes | Yes | Yes |
| AWQ | Yes | Yes | Yes | Yes |
| INT8 (W8A8) | Yes | Yes | Yes | Yes |
| FP8 (W8A8) | **No** | **No** | Yes | Yes |
| Marlin (GPTQ/AWQ/FP8) | **No** | Yes | Yes | Yes |

This matrix reflects vLLM stable (v0.15.x). If running v0.16+ or nightly, re-check the upstream supported-hardware table as kernel support evolves.

### 70B on 96GB Path

Use RedHatAI's INT4 GPTQ quantized Llama 3.1 70B (`RedHatAI/Meta-Llama-3.1-70B-Instruct-quantized.w4a16`). This reduces weights by ~75% (from ~140GB to ~35GB), leaving ~60GB for KV cache and overhead.

```bash
vllm serve RedHatAI/Meta-Llama-3.1-70B-Instruct-quantized.w4a16 \
  --tensor-parallel-size 2 \
  --dtype auto \
  --gpu-memory-utilization 0.90 \
  --max-model-len 4096 \
  --max-num-batched-tokens 2048
```

**Assumptions:** 2x RTX 6000 Ada (96GB total). Context capped at 4096 to preserve KV headroom. For 4x T4 (64GB), use `--tensor-parallel-size 4 --dtype float16` and reduce `--max-model-len` to 2048.

## Troubleshooting Playbooks

### 1. Chat Completions Errors (missing template / wrong content format)

**Most likely cause:** Model lacks a chat template, or content format mismatch.

**How to confirm:** Error message mentions "template", "tokenizer", or "chat format". Check if model has `tokenizer_config.json` with a `chat_template` field.

**Exact fix:**
```bash
# Supply a chat template file
vllm serve <model> --chat-template /path/to/template.jinja

# Or override content format detection
vllm serve <model> --chat-template-content-format openai
```

**If still failing:** Verify the template is valid Jinja2 and matches the model's expected message structure.

### 2. Temperature / top_p Ignored

**Most likely cause:** Model's `generation_config.json` overrides sampling defaults.

**How to confirm:** Check if `<model_dir>/generation_config.json` exists and contains `temperature` or `top_p` values.

**Exact fix:** Add `--generation-config vllm` to the serve command.

**If still failing:** Verify client is actually sending `temperature` in the request body (not relying on server defaults).

### 3. OOM at Model Load vs OOM on First Request

**OOM at load (weights don't fit):**
1. Increase `--tensor-parallel-size` to shard across more GPUs
2. Use a quantized model (INT4/FP8)
3. Try `--cpu-offload-gb <N>` (performance penalty; needs fast CPU-GPU interconnect)

**OOM on first request (KV cache blowup):**
1. Reduce `--max-model-len` (first knob to turn)
2. Reduce `--max-num-batched-tokens`
3. Reduce `--max-num-seqs` (hard cap on concurrent sequences)
4. Lower `--gpu-memory-utilization` (e.g., 0.90 -> 0.85) to leave headroom and reduce allocator pressure
5. If still failing: quantize or reduce model tier

**Sequence:** `--max-model-len` -> `--max-num-batched-tokens` -> `--max-num-seqs` -> `--gpu-memory-utilization` -> `--cpu-offload-gb` -> quantization/smaller model.

### 4. Quantization Load Failures

**Most likely cause:** GPU architecture incompatible with quantization format.

**How to confirm:** Error mentions "kernel", "unsupported", or "marlin"/"fp8". Check GPU with `nvidia-smi --query-gpu=gpu_name,compute_cap --format=csv`.

**Exact fix:** Match GPU to supported formats:
- T4 (SM 7.5): GPTQ, AWQ, INT8 only; no FP8 or Marlin
- L4/Ada (SM 8.9): All formats including FP8 W8A8 and Marlin
- Use `--load-format auto` (default) and ensure the model repo matches your GPU's capabilities.

**If still failing:** Try a differently-quantized version of the same model (e.g., GPTQ instead of FP8).

### 5. Air-Gapped Failures

**Most likely cause:** vLLM or HuggingFace SDK attempting network access.

**How to confirm:** Errors mentioning "connection", "timeout", "huggingface.co", or "resolve host".

**Exact fix:**
```bash
# 1. Set offline mode
export HF_HUB_OFFLINE=1

# 2. Serve from local path (not model name)
vllm serve /local/models/my-model --download-dir /local/models/my-model

# 3. Enable offline docs
vllm serve ... --enable-offline-docs
```

**If still failing:** Verify all model files are present locally (config.json, tokenizer files, safetensors/bin weights). Sometimes you must use the full HF cache snapshot path: `~/.cache/huggingface/hub/models--org--name/snapshots/<hash>/`.

### 6. Client Schema Mismatch (structured outputs / reasoning fields)

**Structured outputs (pre vs post v0.12.0):**
- Pre-v0.12.0: clients sent `guided_json`, `guided_regex`, etc.
- Post-v0.12.0: these fields removed; use `structured_outputs` in `extra_body`
- **Fix:** Update client to use `extra_body={"structured_outputs": {...}}`

**Reasoning field names:**
- Current vLLM (>= v0.12.0): response contains `reasoning` (with `reasoning_content` backcompat until v0.16.0)
- Legacy vLLM (<= v0.11.x): response contains `reasoning_content` only
- v0.16.0+: `reasoning_content` removed entirely
- **Fix:** Prefer `reasoning`. Fall back to `reasoning_content` only when talking to vLLM < v0.12.0.

## Client Usage and API Extensions

### OpenAI Client Configuration

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8000/v1",
    api_key="your-vllm-api-key",  # must match --api-key
)
```

### extra_body for vLLM-Only Parameters

```python
response = client.chat.completions.create(
    model="meta-llama/Llama-3.1-8B-Instruct",
    messages=[{"role": "user", "content": "Hello"}],
    extra_body={
        "top_k": 50,                # vLLM extension
        "repetition_penalty": 1.1,  # vLLM extension
    },
)
```

### Structured Outputs (v0.12.0+)

```python
response = client.chat.completions.create(
    model="meta-llama/Llama-3.1-8B-Instruct",
    messages=[{"role": "user", "content": "List 3 US cities as JSON"}],
    extra_body={
        "structured_outputs": {
            "json": {
                "type": "object",
                "properties": {
                    "cities": {"type": "array", "items": {"type": "string"}}
                },
                "required": ["cities"],
            },
        },
    },
)
```

### Reasoning Output Handling

Some models have thinking disabled by default and require explicit enablement:
- **Server-wide:** `--default-chat-template-kwargs '{"thinking": true}'`
- **Per-request:** `extra_body={"chat_template_kwargs": {"thinking": True}}`

Models with thinking enabled by default can be disabled similarly with `{"enable_thinking": false}`.

```python
# Server must be started with --reasoning-parser <parser_name>
response = client.chat.completions.create(
    model="your-reasoning-model",
    messages=[{"role": "user", "content": "Solve: 2x + 3 = 7"}],
)

msg = response.choices[0].message
# "reasoning" is current (v0.12.0+). "reasoning_content" is legacy (<= v0.11.x).
# v0.16.0 removes reasoning_content entirely.
reasoning = getattr(msg, 'reasoning', None) or getattr(msg, 'reasoning_content', None)
content = msg.content
```

For streaming, access reasoning via dynamic attributes:
```python
for chunk in stream:
    delta = chunk.choices[0].delta
    # Prefer current field; legacy fallback for older vLLM only
    r = getattr(delta, 'reasoning', None) or getattr(delta, 'reasoning_content', None)
    if r:
        print(r, end='')
    if delta.content:
        print(delta.content, end='')
```

### Tool Calling

```python
response = client.chat.completions.create(
    model="meta-llama/Llama-3.1-8B-Instruct",
    messages=[{"role": "user", "content": "What's the weather in NYC?"}],
    tools=[{
        "type": "function",
        "function": {
            "name": "get_weather",
            "description": "Get weather for a location",
            "parameters": {
                "type": "object",
                "properties": {"location": {"type": "string"}},
                "required": ["location"],
            },
        },
    }],
    tool_choice="auto",
    extra_body={"parallel_tool_calls": False},  # 0 or 1 tool call only
)
```

Set `parallel_tool_calls=True` to allow multiple simultaneous tool calls (model-dependent behavior).

## Self-Test Checklist

### Command Templates (TP=1/2/4)

```bash
# TP=1 (single GPU)
vllm serve meta-llama/Llama-3.1-8B-Instruct --dtype auto --api-key test

# TP=2
vllm serve meta-llama/Llama-3.1-8B-Instruct --tensor-parallel-size 2 --dtype auto --api-key test

# TP=4
vllm serve meta-llama/Llama-3.1-8B-Instruct --tensor-parallel-size 4 --dtype auto --api-key test
```

### Air-Gapped Test

```bash
HF_HUB_OFFLINE=1 vllm serve /local/models/Llama-3.1-8B-Instruct \
  --download-dir /local/models/Llama-3.1-8B-Instruct \
  --enable-offline-docs --api-key test
# Verify: curl http://localhost:8000/docs (should render without internet)
```

### Structured Outputs Test

```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer test" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta-llama/Llama-3.1-8B-Instruct",
    "messages": [{"role": "user", "content": "Return JSON: {\"name\": \"test\"}"}],
    "structured_outputs": {"json": {"type": "object", "properties": {"name": {"type": "string"}}, "required": ["name"]}}
  }'
```

### Production Contract Test

```bash
# 1. Verify server-advertised model names
curl -s http://localhost:8000/v1/models -H "Authorization: Bearer test" | jq .

# 2. Ensure request model matches exposed name exactly
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer test" \
  -H "Content-Type: application/json" \
  -H "X-Request-Id: smoke-001" \
  -d '{
    "model": "llama31-8b-prod",
    "messages": [{"role": "user", "content": "Reply with OK"}],
    "max_tokens": 8
  }'
```

### Reasoning Outputs Test

```bash
# Start server with reasoning parser
vllm serve <reasoning-model> --reasoning-parser deepseek_r1 --api-key test

# Test request
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer test" \
  -H "Content-Type: application/json" \
  -d '{"model": "<reasoning-model>", "messages": [{"role": "user", "content": "What is 25 * 37?"}]}'
# Check response for "reasoning" or "reasoning_content" field
```

### OOM Recovery Knob Sequence

Reduce in this order until stable:

```bash
# Step 1: Cap context length
--max-model-len 4096      # then try 2048 if still OOM

# Step 2: Cap batch size
--max-num-batched-tokens 2048   # then try 1024

# Step 3: Cap active sequences (concurrency)
--max-num-seqs 8                # then try 4

# Step 4: Lower GPU memory fraction for extra headroom
--gpu-memory-utilization 0.85   # then try 0.80

# Step 5: Offload weights to CPU (performance penalty)
--cpu-offload-gb 4              # increase as needed

# Step 6: Switch to quantized model or smaller model tier
```

## Reference Files

| File | Contents | Load when |
|---|---|---|
| `references/reference.md` | Detailed hardware profiles (4xT4, 4xL4, 2xAda), full memory math, complete quantization matrix, air-gapped deployment playbook, production operations checklist (systemd/container hardening, rollout/rollback, observability), extended troubleshooting with fallback steps, V0-to-V1 migration detail, full API examples | Building a specific hardware profile, preparing a production rollout, debugging a complex deployment issue, or planning an air-gapped installation |
