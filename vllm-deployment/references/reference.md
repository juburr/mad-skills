# Reference

Detailed hardware deployment profiles, memory math, quantization matrix, air-gapped playbook, V0-to-V1 migration, extended troubleshooting, and full API examples for vLLM deployments.

## Table of Contents

- [Memory Math Primer](#memory-math-primer)
- [Production Operations Playbook](#production-operations-playbook)
- [Detailed Hardware Profiles](#detailed-hardware-profiles)
- [Complete Quantization Compatibility Matrix](#complete-quantization-compatibility-matrix)
- [Air-Gapped Deployment Playbook](#air-gapped-deployment-playbook)
- [V0 to V1 Engine Migration](#v0-to-v1-engine-migration)
- [Extended Troubleshooting](#extended-troubleshooting)
- [Full API Examples](#full-api-examples)

## Memory Math Primer

### Weights Memory

| Precision | Bytes/Param | 8B Model | 27B Model | 35B Model | 70B Model |
|---|---|---|---|---|---|
| BF16 / FP16 | 2 | ~16 GB | ~54 GB | ~70 GB | ~140 GB |
| FP8 (W8A8) | 1 | ~8 GB | ~27 GB | ~35 GB | ~70 GB |
| INT4 (GPTQ/AWQ) | 0.5 + overhead | ~5 GB | ~15 GB | ~20 GB | ~38 GB |

These are weight-only estimates. Actual GPU memory also includes:
- **KV cache** (proportional to `max_model_len` x `num_heads` x `head_dim` x `num_layers` x batch_size x 2 (K+V) x dtype_size)
- **Activation memory** during forward pass
- **CUDA overhead** and fragmentation (~1-3 GB)

### KV Cache Impact

KV cache is where most runtime OOMs originate. The key relationship:

```
KV cache memory ∝ max_model_len × max_concurrent_requests × model_hidden_size × num_layers
```

Practical implications:
- Doubling `--max-model-len` roughly doubles KV cache memory
- Doubling concurrency roughly doubles KV cache memory
- A 70B model with 32k context needs significantly more KV cache than with 4k context

**Rule of thumb for 96GB total VRAM:**
- After loading weights, the remaining VRAM is your KV cache budget
- 70B INT4 (~38GB weights) leaves ~58GB for KV cache and overhead on 96GB
- 27B FP16 (~54GB weights) leaves ~42GB for KV cache and overhead on 96GB

### vLLM Memory Controls Hierarchy

These flags control how memory is allocated, in order of typical impact:

| Flag | What It Controls | Default | Reduce When |
|---|---|---|---|
| `--max-model-len` | Maximum sequence length (caps KV cache per request) | Model's config value | OOM on first request; model has large default (32k/128k) |
| `--max-num-batched-tokens` | Max tokens processed in a single batch | Varies | OOM during high-concurrency batches |
| `--max-num-seqs` | Max number of concurrent sequences | Context-dependent in `vllm serve` (commonly 256; can be 1024 on high-memory GPUs) | OOM under concurrent traffic; latency spikes from over-admission |
| `--gpu-memory-utilization` | Fraction of GPU memory vLLM may use | 0.9 | OOM at startup; other processes need GPU memory |
| `--cpu-offload-gb` | GB of weights offloaded to CPU per GPU | 0 | Model barely doesn't fit; fast CPU-GPU interconnect available |
| `--tensor-parallel-size` | Number of GPUs to shard weights across | 1 | Model too large for single GPU |

## Production Operations Playbook

### 1. Preflight Before Any Rollout

Capture these artifacts before deploying:

```bash
vllm --version
python -c "import torch; print(torch.__version__, torch.version.cuda)"
nvidia-smi
```

Then validate:
- vLLM version and release channel (stable vs pre-release) are intentional
- torch/CUDA runtime and NVIDIA driver are compatible
- chosen quantization format is supported by your GPU architecture

### 2. Deterministic Serving Contract

Avoid implicit defaults in production:

```bash
vllm serve <model_or_local_path> \
  --served-model-name <stable-client-model-name> \
  --api-key "${VLLM_API_KEY}" \
  --generation-config vllm \
  --max-model-len 4096 \
  --max-num-batched-tokens 2048 \
  --max-num-seqs 8
```

Why this matters:
- `--served-model-name` decouples client-facing API name from HF path/local directory
- explicit memory/admission caps prevent accidental regressions during model swaps
- `--generation-config vllm` avoids hidden sampling behavior from model-side config files

### 3. Security Hardening Baseline

- Keep TLS/authN/authZ at an ingress or reverse proxy; treat vLLM's `--api-key` as a minimum control, not full security.
- Use high-entropy API keys from env/secret stores; avoid embedding secrets in shell history or scripts.
- Do not enable `--trust-remote-code` unless the model repository is reviewed and mirrored internally.
- Prefer immutable local model paths (read-only mounts in containers) for repeatable deployments.

### 4. Rollout and Rollback Policy

1. Deploy new version to a canary slice first.
2. Run smoke checks (`/v1/models`, one chat completion, one structured output request).
3. Observe 5xx rate, p95/p99 latency, GPU memory headroom, and OOM frequency.
4. Promote gradually; keep last known-good image and model snapshot ready for immediate rollback.

### 5. Minimal systemd Unit (Bare-Metal)

```ini
[Unit]
Description=vLLM OpenAI Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
# Store secrets in a root-owned env file, e.g. /etc/vllm/vllm.env (chmod 600)
EnvironmentFile=/etc/vllm/vllm.env
ExecStart=/usr/bin/vllm serve /models/Llama-3.1-8B-Instruct \
  --served-model-name llama31-8b-prod \
  --api-key ${VLLM_API_KEY} \
  --dtype auto \
  --generation-config vllm \
  --max-model-len 4096 \
  --max-num-batched-tokens 2048 \
  --max-num-seqs 8 \
  --enable-request-id-headers
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
```

## Detailed Hardware Profiles

### Profile 1: 4x T4 (16 GB each, 64 GB total)

**Architecture:** Turing (SM 7.5). No BF16 compute, no FP8 kernels, no Marlin.

**Constraints:**
- Must use `--dtype float16` (BF16 not supported)
- Quantization limited to GPTQ, AWQ, INT8; no FP8 or Marlin
- 16 GB per GPU means tight headroom for KV cache after weight sharding

**Recommended configurations:**

| Model Tier | Example Model | TP | dtype | max_model_len | gpu_mem_util | Notes |
|---|---|---|---|---|---|---|
| A (8B) | Llama 3.1 8B Instruct | 1-2 | float16 | 4096-8192 | 0.85 | Single GPU works; TP=2 for longer context |
| B (14B) | Phi-4-reasoning 14B | 2-4 | float16 | 4096 | 0.85 | TP=4 for comfortable headroom |
| C (27B) | Gemma 2 27B | 4 | float16 | 4096 | 0.85 | Tight fit; monitor memory closely |
| E (70B INT4) | RedHatAI Llama 3.1 70B w4a16 | 4 | float16 | 2048 | 0.85 | Very tight; minimal concurrency |

**Template command (Tier A, single T4):**
```bash
vllm serve meta-llama/Llama-3.1-8B-Instruct \
  --served-model-name llama31-8b-prod \
  --dtype float16 \
  --gpu-memory-utilization 0.85 \
  --max-model-len 4096 \
  --max-num-batched-tokens 2048 \
  --max-num-seqs 8 \
  --generation-config vllm \
  --api-key "${VLLM_API_KEY}"
```

**Template command (Tier E, 70B INT4 on 4xT4):**
```bash
vllm serve RedHatAI/Meta-Llama-3.1-70B-Instruct-quantized.w4a16 \
  --served-model-name llama31-70b-int4-prod \
  --tensor-parallel-size 4 \
  --dtype float16 \
  --gpu-memory-utilization 0.85 \
  --max-model-len 2048 \
  --max-num-batched-tokens 1024 \
  --max-num-seqs 4 \
  --generation-config vllm \
  --api-key "${VLLM_API_KEY}"
```

### Profile 2: 4x L4 (24 GB each, 96 GB total)

**Architecture:** Ada Lovelace (SM 8.9). Full FP8 and Marlin kernel support.

**Advantages:**
- FP8 quantization available (halves weight memory vs FP16 with minimal quality loss)
- Marlin kernels accelerate GPTQ/AWQ inference
- 24 GB per GPU provides more per-shard headroom than T4

**Recommended configurations:**

| Model Tier | Example Model | TP | dtype | max_model_len | gpu_mem_util | Notes |
|---|---|---|---|---|---|---|
| A (8B) | Llama 3.1 8B Instruct | 1 | auto | 8192 | 0.90 | Single GPU, generous context |
| C (27B) | Gemma 2 27B | 2-4 | auto | 8192 | 0.90 | TP=2 is comfortable |
| D (35B) | Command-R 35B | 4 | auto | 4096 | 0.88 | Conservative context recommended |
| E (70B INT4) | RedHatAI Llama 3.1 70B w4a16 | 4 | auto | 4096 | 0.90 | Good balance of quality and headroom |
| E (70B FP8) | FP8 quantized 70B | 4 | auto | 4096 | 0.90 | Slightly better quality than INT4 |

**Template command (Tier C, 27B on 4xL4):**
```bash
vllm serve google/gemma-2-27b-it \
  --served-model-name gemma2-27b-prod \
  --tensor-parallel-size 4 \
  --dtype auto \
  --gpu-memory-utilization 0.90 \
  --max-model-len 8192 \
  --max-num-seqs 8 \
  --generation-config vllm \
  --api-key "${VLLM_API_KEY}"
```

**Template command (Tier E, 70B INT4 on 4xL4):**
```bash
vllm serve RedHatAI/Meta-Llama-3.1-70B-Instruct-quantized.w4a16 \
  --served-model-name llama31-70b-int4-prod \
  --tensor-parallel-size 4 \
  --dtype auto \
  --gpu-memory-utilization 0.90 \
  --max-model-len 4096 \
  --max-num-batched-tokens 2048 \
  --max-num-seqs 8 \
  --generation-config vllm \
  --api-key "${VLLM_API_KEY}"
```

### Profile 3: 2x RTX 6000 Ada (48 GB each, 96 GB total)

**Architecture:** Ada Lovelace (SM 8.9). Same kernel support as L4.

**Advantages:**
- Fewer GPUs = simpler TP topology (TP=2)
- 48 GB per GPU provides excellent per-shard headroom
- Ideal for 27-35B FP16 or 70B quantized

**Recommended configurations:**

| Model Tier | Example Model | TP | dtype | max_model_len | gpu_mem_util | Notes |
|---|---|---|---|---|---|---|
| A (8B) | Llama 3.1 8B Instruct | 1 | auto | 16384 | 0.90 | Generous context on single GPU |
| C (27B) | Gemma 2 27B (FP16) | 2 | auto | 8192 | 0.90 | Comfortable fit |
| D (35B) | Command-R 35B | 2 | auto | 8192 | 0.88 | ~35GB weights per GPU; watch KV |
| E (70B INT4) | RedHatAI Llama 3.1 70B w4a16 | 2 | auto | 8192 | 0.92 | Best 70B profile: TP=2 is simpler |
| E (70B FP8) | FP8 quantized 70B | 2 | auto | 4096 | 0.90 | ~35GB weights per GPU; less KV room than INT4 |

**Template command (Tier E, 70B INT4 on 2x Ada):**
```bash
vllm serve RedHatAI/Meta-Llama-3.1-70B-Instruct-quantized.w4a16 \
  --served-model-name llama31-70b-int4-prod \
  --tensor-parallel-size 2 \
  --dtype auto \
  --gpu-memory-utilization 0.92 \
  --max-model-len 8192 \
  --max-num-batched-tokens 4096 \
  --max-num-seqs 8 \
  --generation-config vllm \
  --api-key "${VLLM_API_KEY}"
```

## Complete Quantization Compatibility Matrix

| Method | Volta (V100) | Turing (T4) | Ampere (A100) | Ada (L4, RTX 6000) | Hopper (H100) |
|---|---|---|---|---|---|
| GPTQ | Yes | Yes | Yes | Yes | Yes |
| AWQ | No | Yes | Yes | Yes | Yes |
| INT8 (W8A8) | No | Yes | Yes | Yes | Yes |
| FP8 (W8A8) | No | **No** | No | **Yes** | **Yes** |
| Marlin (GPTQ/AWQ/FP8) | No | **No** | Yes | **Yes** | **Yes** |
| bitsandbytes | Yes | Yes | Yes | Yes | Yes |

**Key takeaway:** In v0.15.x stable, T4 users cannot use FP8 or Marlin-accelerated formats. Ada/Hopper users have the full range. For v0.16+/nightly, re-check upstream because quantization kernel support is evolving.

## Air-Gapped Deployment Playbook

### Step 1: Download Model (on connected machine)

```python
# Using huggingface_hub
from huggingface_hub import snapshot_download

snapshot_download(
    "meta-llama/Llama-3.1-8B-Instruct",
    local_dir="/export/models/Llama-3.1-8B-Instruct",
    local_dir_use_symlinks=False,  # actual files, not symlinks
)
```

Or via CLI:
```bash
huggingface-cli download meta-llama/Llama-3.1-8B-Instruct \
  --local-dir /export/models/Llama-3.1-8B-Instruct
```

### Step 2: Transfer to Air-Gapped System

Copy the entire model directory to the disconnected host. Verify all files are present:
- `config.json`
- `tokenizer.json` and `tokenizer_config.json`
- `*.safetensors` (or `*.bin`) weight files
- `generation_config.json` (optional but commonly present)
- `special_tokens_map.json`

### Step 3: Install vLLM Offline

```bash
# On connected machine: download wheels
pip download vllm --dest /export/wheels/

# Transfer /export/wheels/ to air-gapped host
# On air-gapped host:
pip install --no-index --find-links /export/wheels/ vllm
```

Or use a pre-built container image:
```bash
# Pull on connected machine
podman pull vllm/vllm-openai:v0.15.1

# Save and transfer
podman save vllm/vllm-openai:v0.15.1 -o vllm-openai-v0.15.1.tar

# Load on air-gapped host
podman load -i vllm-openai-v0.15.1.tar
```

### Step 4: Serve from Local Path

```bash
export HF_HUB_OFFLINE=1

vllm serve /local/models/Llama-3.1-8B-Instruct \
  --download-dir /local/models/Llama-3.1-8B-Instruct \
  --dtype auto \
  --gpu-memory-utilization 0.85 \
  --max-model-len 4096 \
  --enable-offline-docs \
  --api-key "${VLLM_API_KEY}"
```

**Critical:** Use the **local directory path** as the model argument, not a HuggingFace model ID. Setting `HF_HUB_OFFLINE=1` prevents any network calls to huggingface.co.

### Step 5: Verify

```bash
# Check /docs works offline
curl -s http://localhost:8000/docs | head -5

# Check model serves
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer ${VLLM_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/local/models/Llama-3.1-8B-Instruct",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 50
  }'
```

### HF Cache Snapshot Path Pitfall

If you used HuggingFace's default caching (instead of `--local-dir`), the model files may be stored at a path like:
```
~/.cache/huggingface/hub/models--meta-llama--Llama-3.1-8B-Instruct/snapshots/<hash>/
```

You must serve from this **full snapshot path**, not the `models--` parent directory.

## V0 to V1 Engine Migration

### Behavioral Differences

| Behavior | V0 (pre-v0.8.1 default) | V1 (v0.8.1+ default, only engine v0.11.0+) |
|---|---|---|
| Prefix caching | Disabled by default | Enabled by default |
| Scheduler | Legacy continuous batching | Improved scheduler with better memory management |
| Feature support | All legacy features | Some V0-only features removed (see below) |

### Removed V0 Features (v0.10.0+)

These features were only available in V0 and were removed:
- V0 CPU/XPU/TPU/HPU backends
- Long-context LoRA
- Prompt Adapters
- Phi3-Small and block-sparse attention
- Spec-decode workers (original implementation)

### Migration Checklist

1. Remove `VLLM_USE_V1=0` from environment if present (V0 no longer exists in v0.11.0+)
2. If you explicitly disabled prefix caching, note it is now enabled by default; add `--no-enable-prefix-caching` to restore old behavior if needed
3. Test with V1 before upgrading past v0.11.0 by running v0.8.1-v0.10.x with V1 as default
4. Review any custom attention configuration -- environment variable config was replaced by CLI arguments in v0.13.0

## Extended Troubleshooting

### "vllm serve: error: the following arguments are required: model_tag"

**Cause:** On older vLLM versions, the model was a required positional argument. Current vLLM accepts both positional and `--model` flag forms and may load a default model if omitted.

**Fix:** Either form works on current vLLM:
```bash
vllm serve meta-llama/Llama-3.1-8B-Instruct                # positional
vllm serve --model meta-llama/Llama-3.1-8B-Instruct        # flag
```

If you see this error on an older version, use the positional form. On newer versions, still specify model explicitly to avoid silent default-model mismatches.

### "Model not found" / 404 on chat request

**Cause:** Client `model` value does not match the server's exposed model name.

**Diagnostic:**
```bash
curl -s http://localhost:8000/v1/models -H "Authorization: Bearer ${VLLM_API_KEY}" | jq .
```

**Fix options:**
1. Set `--served-model-name <stable-name>` on server startup.
2. Update client to send exactly that model name.
3. Re-test with a single minimal request before restoring traffic.

### "RuntimeError: CUDA out of memory" During Model Loading

**Diagnostic sequence:**

1. **Check weight size vs available VRAM:**
   ```bash
   nvidia-smi  # check free memory
   # Compare against: params × bytes_per_param
   ```

2. **Try with lower utilization:**
   ```bash
   --gpu-memory-utilization 0.80
   ```

3. **Increase tensor parallelism:**
   ```bash
   --tensor-parallel-size 2  # or 4
   ```

4. **Offload to CPU (last resort):**
   ```bash
   --cpu-offload-gb 4
   ```

5. **Switch to quantized model**

### "CUDA error: no kernel image is available for execution on the device"

**Cause:** The model's quantization format requires a GPU architecture that your hardware doesn't support.

**Common cases:**
- FP8 model on T4 (needs Ada/Hopper)
- Marlin-format model on T4 (needs Ampere+)

**Fix:** Use a GPTQ or AWQ quantized version of the same model.

### "No chat template found" or Template-Related 500 Errors

**Diagnostic:**
```python
from transformers import AutoTokenizer
tok = AutoTokenizer.from_pretrained("your-model")
print(tok.chat_template)  # None means no template
```

**Fix options:**
1. Use the instruct/chat variant of the model (e.g., `Llama-3.1-8B-Instruct` not `Llama-3.1-8B`)
2. Supply a template: `--chat-template /path/to/template.jinja`
3. Use `/v1/completions` instead of `/v1/chat/completions` (raw text completion, no template needed)

### Structured Outputs Return 400/422 After Upgrade to v0.12.0+

**Old client code (broken):**
```python
response = client.chat.completions.create(
    model="model",
    messages=[...],
    extra_body={"guided_json": {"type": "object", ...}},  # REMOVED in v0.12.0
)
```

**Fixed client code:**
```python
response = client.chat.completions.create(
    model="model",
    messages=[...],
    extra_body={
        "structured_outputs": {
            "json": {"type": "object", ...},
        },
    },
)
```

### Reasoning Outputs Missing or Field Name Mismatch

**Server configuration required:**
```bash
vllm serve <reasoning-model> --reasoning-parser deepseek_r1
```

Note: Very early versions (v0.8.x) also required `--enable-reasoning`. Current vLLM only needs `--reasoning-parser`.

**Thinking mode may need explicit enablement.** Some models have thinking disabled by default. If `reasoning` is missing from responses despite `--reasoning-parser` being set:
- Enable server-wide: `--default-chat-template-kwargs '{"thinking": true}'`
- Enable per-request: `extra_body={"chat_template_kwargs": {"thinking": True}}`
- To disable thinking on models where it's on by default: use `{"enable_thinking": false}` instead

**Field name history:**
- `reasoning_content` (<= v0.11.x): the original field name
- `reasoning` (v0.12.0+): current field name; `reasoning_content` kept for backcompat
- v0.16.0+: `reasoning_content` **removed** entirely

**Client-side defensive parsing:**
```python
msg = response.choices[0].message

# "reasoning" is current (v0.12.0+). "reasoning_content" is legacy (<= v0.11.x), removed in v0.16.0.
reasoning = getattr(msg, 'reasoning', None) or getattr(msg, 'reasoning_content', None)
content = msg.content
```

**For streaming:**
```python
for chunk in stream:
    delta = chunk.choices[0].delta
    # "reasoning" is current (v0.12.0+); legacy fallback for older vLLM
    r = getattr(delta, 'reasoning', None) or getattr(delta, 'reasoning_content', None)
    if r:
        print(f"[thinking] {r}", end='')
    if delta.content:
        print(delta.content, end='')
```

### Model Loads But Inference is Extremely Slow

**Possible causes:**
1. **CPU offload active:** Check if `--cpu-offload-gb` is set. CPU-GPU data transfer is a bottleneck.
2. **dtype mismatch:** Running FP32 instead of FP16/BF16. Ensure `--dtype auto` or `--dtype float16/bfloat16`.
3. **Excessive context length:** Very large `--max-model-len` causes larger KV cache operations per step.
4. **Admission too high:** `--max-num-seqs` too large can overload memory and scheduler.
5. **Single GPU when model could be sharded:** Increase `--tensor-parallel-size` for compute parallelism.

### Container Deployment Templates

**Docker:**
```bash
docker run --rm -it \
  --runtime nvidia --gpus all \
  --ipc=host \
  -v /local/models:/models \
  -p 8000:8000 \
  -e HF_HUB_OFFLINE=1 \
  vllm/vllm-openai:v0.15.1 \
  --model /models/Llama-3.1-8B-Instruct \
  --served-model-name llama31-8b-prod \
  --download-dir /models/Llama-3.1-8B-Instruct \
  --dtype auto \
  --gpu-memory-utilization 0.85 \
  --max-model-len 4096 \
  --max-num-seqs 8 \
  --enable-offline-docs \
  --api-key "${VLLM_API_KEY}"
```

**Podman (single GPU):**
```bash
podman run --rm -it \
  --device nvidia.com/gpu=all \
  --ipc=host \
  -v /local/models:/models:Z \
  -p 8000:8000 \
  -e HF_HUB_OFFLINE=1 \
  docker.io/vllm/vllm-openai:v0.15.1 \
  --model /models/Llama-3.1-8B-Instruct \
  --served-model-name llama31-8b-prod \
  --download-dir /models/Llama-3.1-8B-Instruct \
  --dtype auto \
  --gpu-memory-utilization 0.85 \
  --max-model-len 4096 \
  --max-num-seqs 8 \
  --enable-offline-docs \
  --api-key "${VLLM_API_KEY}"
```

**Podman (multi-GPU):**
```bash
podman run --rm -it \
  --device nvidia.com/gpu=all \
  --ipc=host \
  -v /local/models:/models:Z \
  -p 8000:8000 \
  docker.io/vllm/vllm-openai:v0.15.1 \
  --model /models/Llama-3.1-8B-Instruct \
  --served-model-name llama31-8b-prod \
  --tensor-parallel-size 4 \
  --dtype auto \
  --max-num-seqs 8 \
  --api-key "${VLLM_API_KEY}"
```

`--ipc=host` (or `--shm-size`) is required — PyTorch uses shared memory for tensor parallel inference and will hang or crash without it.

## Full API Examples

### Complete Chat Completion with All Extensions

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8000/v1",
    api_key="your-key",
)

# Basic chat
response = client.chat.completions.create(
    model="meta-llama/Llama-3.1-8B-Instruct",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Explain TCP/IP in one paragraph."},
    ],
    temperature=0.7,
    max_tokens=256,
)
print(response.choices[0].message.content)
```

### Structured Outputs with JSON Schema

```python
schema = {
    "type": "object",
    "properties": {
        "name": {"type": "string"},
        "age": {"type": "integer"},
        "skills": {
            "type": "array",
            "items": {"type": "string"},
        },
    },
    "required": ["name", "age", "skills"],
}

response = client.chat.completions.create(
    model="meta-llama/Llama-3.1-8B-Instruct",
    messages=[{"role": "user", "content": "Create a profile for a software engineer named Alex"}],
    extra_body={
        "structured_outputs": {
            "json": schema,
        },
    },
)

import json
profile = json.loads(response.choices[0].message.content)
```

### Structured Outputs with Regex

```python
response = client.chat.completions.create(
    model="meta-llama/Llama-3.1-8B-Instruct",
    messages=[{"role": "user", "content": "Generate an IP address"}],
    extra_body={
        "structured_outputs": {
            "regex": r"\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}",
        },
    },
)
```

### Structured Outputs with Choice Constraint

```python
response = client.chat.completions.create(
    model="meta-llama/Llama-3.1-8B-Instruct",
    messages=[{"role": "user", "content": "What color is the sky?"}],
    extra_body={
        "structured_outputs": {
            "choice": ["blue", "gray", "red", "orange"],
        },
    },
)
```

### Tool Calling with Parallel Control

```python
tools = [
    {
        "type": "function",
        "function": {
            "name": "get_weather",
            "description": "Get current weather",
            "parameters": {
                "type": "object",
                "properties": {
                    "location": {"type": "string", "description": "City name"},
                    "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]},
                },
                "required": ["location"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_time",
            "description": "Get current time in a timezone",
            "parameters": {
                "type": "object",
                "properties": {
                    "timezone": {"type": "string"},
                },
                "required": ["timezone"],
            },
        },
    },
]

# Single tool call only
response = client.chat.completions.create(
    model="meta-llama/Llama-3.1-8B-Instruct",
    messages=[{"role": "user", "content": "What's the weather in NYC?"}],
    tools=tools,
    tool_choice="auto",
    extra_body={"parallel_tool_calls": False},  # 0 or 1 tool call
)

# Allow parallel tool calls (model-dependent)
response = client.chat.completions.create(
    model="meta-llama/Llama-3.1-8B-Instruct",
    messages=[{"role": "user", "content": "Weather in NYC and time in Tokyo?"}],
    tools=tools,
    tool_choice="auto",
    extra_body={"parallel_tool_calls": True},  # may return multiple tool calls
)

# Process tool calls
for choice in response.choices:
    if choice.message.tool_calls:
        for tc in choice.message.tool_calls:
            print(f"Call: {tc.function.name}({tc.function.arguments})")
```

### Streaming with Token-Level Output

```python
stream = client.chat.completions.create(
    model="meta-llama/Llama-3.1-8B-Instruct",
    messages=[{"role": "user", "content": "Write a haiku about servers"}],
    stream=True,
    max_tokens=100,
)

for chunk in stream:
    if chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end='', flush=True)
print()
```

### Completions API (non-chat, no template needed)

```python
response = client.completions.create(
    model="meta-llama/Llama-3.1-8B-Instruct",
    prompt="The capital of France is",
    max_tokens=10,
    temperature=0.0,
)
print(response.choices[0].text)
```

### Version Detection Snippet

```python
import subprocess
import re

def get_vllm_version():
    """Detect installed vLLM version."""
    try:
        result = subprocess.run(['vllm', '--version'], capture_output=True, text=True)
        return result.stdout.strip()
    except FileNotFoundError:
        pass
    try:
        result = subprocess.run(['pip', 'show', 'vllm'], capture_output=True, text=True)
        for line in result.stdout.splitlines():
            if line.startswith('Version:'):
                return line.split(':')[1].strip()
    except FileNotFoundError:
        pass
    return "unknown"

def check_feature_support(version_str):
    """Check which features are available at this version."""
    try:
        parts = version_str.lstrip('v').split('.')
        major, minor = int(parts[0]), int(parts[1])
        ver = (major, minor)
    except (ValueError, IndexError):
        return {"error": f"Cannot parse version: {version_str}"}

    return {
        "v1_engine_default": ver >= (0, 8),
        "v0_removed": ver >= (0, 11),
        "structured_outputs_new_api": ver >= (0, 12),
        "reasoning_field_name": "reasoning" if ver >= (0, 12) else "reasoning_content",  # reasoning_content removed in v0.16.0
        "reasoning_content_removed": ver >= (0, 16),
        "offline_docs": ver >= (0, 14),
    }
```

## Primary Sources for Ongoing Maintenance

Use these sources when updating this skill for new vLLM releases:

- GitHub releases (release status, breaking changes): `https://github.com/vllm-project/vllm/releases`
- OpenAI-compatible server behavior and API nuances: `https://docs.vllm.ai/en/stable/serving/openai_compatible_server/`
- `vllm serve` CLI flags/defaults: `https://docs.vllm.ai/en/stable/cli/serve/`
- Structured outputs migration and schema: `https://docs.vllm.ai/en/stable/features/structured_outputs/`
- Reasoning outputs field semantics: `https://docs.vllm.ai/en/stable/features/reasoning_outputs/`
- Quantization support by GPU family (stable): `https://docs.vllm.ai/en/v0.15.0/features/quantization/supported_hardware.html`
- Quantization support (latest preview; verify before claiming): `https://docs.vllm.ai/en/latest/features/quantization/supported_hardware/`
- Hugging Face offline mode behavior: `https://huggingface.co/docs/transformers/installation#offline-mode`
