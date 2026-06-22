# Gemini Deep Research Prompt — 로컬 LLM 모델 선정 및 서버 구축 비용 조사

## Research Goal
I am building an on-premises, self-hosted LLM-based chatbot for internal 
corporate regulation Q&A. I need to:
  1. Select the best open-source LLM for this use case
  2. Determine the on-premises server hardware required for that model
  3. Estimate the total cost (hardware + monthly operation)

Model selection comes first — hardware sizing must follow from the chosen model, 
not the other way around.

---

## Service Overview

**Final product:** Internal corporate regulation Q&A chatbot agent
**Target company size:** 400–500 employees
**Concurrent users:**
  - Normal load: ~10 simultaneous users
  - Peak load (e.g. year-end tax season, HR review period): ~30–50 users
**Architecture:** RAG + LangGraph multi-agent + prompt harness engineering
**Vector DB:** Self-hosted (Chroma or Qdrant)
**Language:** Primarily Korean documents and queries

---

## Deployment Environment

**Production:** On-premises local server inside company network
  - No cloud API dependency for inference (fully self-contained)
  - Inference runtime: Ollama or llama.cpp (Docker containerized)

**Testing/Experiment:** AWS ECS (temporary environment only, used before 
hardware purchase is finalized)
  - Model selection criteria must be based on on-premises constraints, 
    NOT cloud GPU availability
  - Please map each AWS test instance to the equivalent on-premises hardware 
    so benchmark results are transferable

---

## Model Requirements

- **Open-source** with freely available weights
- **Commercial use permitted** (Apache 2.0, MIT, or equivalent)
  → Explicitly state each model's license
- **Speed prioritized over quality**
  → Slightly lower accuracy is acceptable because RAG retrieval compensates
  → Target: first token under 1 second, full response under 5 seconds
- **Korean language support** sufficient for document-based Q&A
  → Does not need to be best-in-class Korean; "good enough" for factual 
    retrieval tasks is fine
- **Runnable via Ollama or llama.cpp** in GGUF format

---

## Research Questions

### 1. Model Selection

Find and compare open-source LLMs (released 2024–2025) that best fit the 
requirements above. Do NOT fix the parameter size in advance — include both 
small (1B–4B) and medium (5B–8B) candidates and let benchmarks decide.

Candidates to evaluate (suggest better options if they exist):
- Qwen2.5 series (1.5B, 3B, 7B)
- Phi-4-mini (3.8B)
- Gemma-3 series (1B, 4B)
- EXAONE-3.5 series (2.4B, 7.8B) — Korean-optimized by LG AI Research
- MiniCPM-3, SmolLM2, or other fast sub-8B models

For each model provide:
- Parameter count
- GGUF Q4_K_M file size (GB)
- Minimum VRAM required (full load)
- Inference speed (tokens/sec) on representative hardware
- Korean benchmark score (KoBEST / HAE-RAE Bench / KMMLU if available)
- License

### 2. Quantization Trade-off

For the top recommended model:
- Compare FP16 vs Q8_0 vs Q4_K_M vs Q4_0
- Speed gain (tokens/sec) at each quantization level
- Quality loss on Korean reading comprehension / fact extraction
- Which quantization level is recommended for RAG-based Q&A?

### 3. On-Premises Hardware Sizing

Based on the recommended model and quantization from above, what server 
hardware is needed to serve 10 concurrent users comfortably, with a path 
to handle 30–50 peak users?

Compare at minimum:
- CPU-only (high RAM, no GPU)
- Single consumer GPU (RTX 3090 / RTX 4090, 24GB VRAM)
- Single server GPU (L4 / A10G, 24GB VRAM)

For each option:
- Max concurrent requests before response time exceeds 5 seconds
- Whether the recommended model fits within VRAM budget
- Recommended inference runtime (Ollama / llama.cpp / vLLM)

### 4. Peak Traffic Strategy

How to handle sudden spikes (30–50 users) on fixed local hardware:
- Request queuing (local middleware)
- Semantic response caching (Redis or similar) for repeated regulation queries
- Prompt/response caching strategies
- Realistic estimate of cache hit rate for typical corporate Q&A patterns

### 5. Cost Estimate

After hardware is determined in Section 3, provide:
- One-time hardware purchase cost (KRW or USD)
- Monthly electricity cost under normal and peak load
- Break-even point compared to running equivalent workload on AWS 
  (g4dn.xlarge or g5.xlarge, 24/7)

---

## Output Format

1. **Model Recommendation** — Top 1–2 picks with justification
2. **Model Comparison Table** — Size, VRAM, speed, Korean score, license
3. **Quantization Recommendation** — Best setting for this use case
4. **Hardware Recommendation** — Spec + why it fits the chosen model
5. **Cost Summary** — Hardware cost, monthly opex, AWS break-even
6. **Peak Traffic Playbook** — Concrete caching/queuing strategies
7. **Sources** — Benchmark links, GitHub repos, papers
