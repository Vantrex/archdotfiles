#!/usr/bin/env python3
"""Quickshell helper for local LLM config management."""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any


HOME = Path(os.environ.get("HOME", "/home/marinus"))
LLAMA_CONFIG = HOME / ".config/llama-swap/config.yaml"
OPENCODE_CONFIG = HOME / ".config/opencode/opencode.json"
OPENCODE_AGENTS = HOME / ".config/opencode/agents"
PI_MODELS = HOME / ".pi/agent/models.json"
PI_SETTINGS = HOME / ".pi/agent/settings.json"
PI_AGENTS = HOME / ".pi/agent/agents"
DEFAULT_MODEL_DIR = HOME / ".lmstudio/models/huggingface"
MODEL_SCAN_ROOTS = [
    HOME / ".lmstudio/models",
    HOME / ".cache/huggingface/hub",
    HOME / ".cache/llama.cpp",
    HOME / "models",
    HOME / "work/llm",
]


def need_ruamel():
    try:
        from ruamel.yaml import YAML  # type: ignore
    except Exception as exc:
        raise RuntimeError("Missing dependency: install python-ruamel-yaml") from exc
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.width = 4096
    return yaml


def read_json(path: Path, fallback: Any) -> Any:
    if not path.exists():
        return fallback
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def write_json_atomic(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        os.replace(tmp_name, path)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def write_text_atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp_name, path)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def backup(path: Path) -> str | None:
    if not path.exists():
        return None
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    dest = path.with_name(f"{path.name}.bak-llm-manager-{stamp}")
    shutil.copy2(path, dest)
    return str(dest)


def load_llama_yaml() -> tuple[Any, Any]:
    yaml = need_ruamel()
    with LLAMA_CONFIG.open("r", encoding="utf-8") as fh:
        return yaml, yaml.load(fh)


def dump_llama_yaml(yaml: Any, data: Any) -> None:
    LLAMA_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=".config.yaml.", suffix=".tmp", dir=LLAMA_CONFIG.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            yaml.dump(data, fh)
        os.replace(tmp_name, LLAMA_CONFIG)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def command_metadata(cmd: str) -> dict[str, Any]:
    meta: dict[str, Any] = {
        "context": None,
        "output": None,
        "vision": "--mmproj" in cmd,
        "cpu": "-ngl 0" in " ".join(cmd.split()),
    }
    try:
        tokens = shlex.split(cmd)
    except ValueError:
        tokens = cmd.split()
    for i, token in enumerate(tokens):
        if token == "-c" and i + 1 < len(tokens):
            meta["context"] = parse_int(tokens[i + 1])
        elif token == "-n" and i + 1 < len(tokens):
            meta["output"] = parse_int(tokens[i + 1])
    return meta


def command_model_path(cmd: str) -> str:
    try:
        tokens = shlex.split(cmd)
    except ValueError:
        tokens = cmd.split()
    for i, token in enumerate(tokens):
        if token == "-m" and i + 1 < len(tokens):
            return tokens[i + 1]
    return ""


def expanded_model_path(path: str, llama_data: Any) -> str:
    if not path:
        return ""
    macros = llama_data.get("macros", {}) if isinstance(llama_data, dict) else {}
    expanded = path
    for key, value in macros.items():
        expanded = expanded.replace("${" + str(key) + "}", str(value))
    expanded = expanded.replace("${env.HOME}", str(HOME)).replace("$HOME", str(HOME))
    return str(Path(expanded).expanduser())


def model_paths_in_router(llama_data: Any) -> set[str]:
    paths: set[str] = set()
    models = llama_data.get("models", {}) if isinstance(llama_data, dict) else {}
    for cfg in models.values():
        if not isinstance(cfg, dict):
            continue
        path = expanded_model_path(command_model_path(str(cfg.get("cmd", ""))), llama_data)
        if path:
            paths.add(path)
    return paths


def parse_int(value: Any) -> int | None:
    try:
        return int(value)
    except Exception:
        return None


def alias_effort(alias_id: str) -> str | None:
    if ":" not in alias_id:
        return None
    suffix = alias_id.rsplit(":", 1)[1]
    return suffix if suffix in {"off", "minimal", "low", "medium", "high", "xhigh"} else None


def normalized_models(llama_data: Any) -> list[dict[str, Any]]:
    models = llama_data.get("models", {}) if isinstance(llama_data, dict) else {}
    out: list[dict[str, Any]] = []
    for model_id, cfg in models.items():
        cfg = cfg or {}
        cmd = str(cfg.get("cmd", ""))
        meta = command_metadata(cmd)
        aliases = []
        params = (((cfg.get("filters") or {}).get("setParamsByID")) or {})
        if isinstance(params, dict):
            aliases = sorted(str(k) for k in params.keys())
        out.append(
            {
                "id": str(model_id),
                "name": str(cfg.get("name", model_id)),
                "description": str(cfg.get("description", "")),
                "ttl": cfg.get("ttl", llama_data.get("ttl", "")),
                "cmd": cmd,
                "path": command_model_path(cmd),
                "aliases": aliases,
                "context": meta["context"],
                "output": meta["output"] or 8192,
                "vision": bool(meta["vision"]),
                "cpu": bool(meta["cpu"] or str(model_id).endswith("-cpu")),
                "reasoning": bool(aliases),
            }
        )
    return out


def human_size(size: int) -> str:
    value = float(size)
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if value < 1024 or unit == "TB":
            return f"{value:.1f} {unit}" if unit != "B" else f"{int(value)} B"
        value /= 1024
    return f"{size} B"


def infer_model_id(path_or_name: str) -> str:
    stem = Path(path_or_name).stem
    stem = re.sub(r"\.(Q[0-9A-Z_]+|I?Q[0-9A-Z_]+|F16|BF16)$", "", stem, flags=re.IGNORECASE)
    stem = re.sub(r"[^A-Za-z0-9]+", "-", stem).strip("-").lower()
    return stem or "local-model"


def unique_model_id(base: str, existing: set[str]) -> str:
    candidate = infer_model_id(base)
    if candidate not in existing:
        return candidate
    for idx in range(2, 1000):
        next_id = f"{candidate}-{idx}"
        if next_id not in existing:
            return next_id
    return f"{candidate}-{int(datetime.now().timestamp())}"


def is_main_gguf(path: Path) -> bool:
    name = path.name.lower()
    if not name.endswith(".gguf"):
        return False
    return not (name.startswith("mmproj") or "mmproj" in name or name.startswith("ggml-vocab"))


def discover_local_models(limit: int = 300) -> list[dict[str, Any]]:
    try:
        _, llama_data = load_llama_yaml()
    except Exception:
        llama_data = {}
    configured = model_paths_in_router(llama_data)
    seen: set[str] = set()
    out: list[dict[str, Any]] = []
    for root in MODEL_SCAN_ROOTS:
        if not root.exists():
            continue
        for file in root.rglob("*"):
            if len(out) >= limit:
                break
            if not file.is_file() or not is_main_gguf(file):
                continue
            path = str(file)
            if path in seen or path in configured:
                continue
            seen.add(path)
            try:
                size = file.stat().st_size
            except OSError:
                size = 0
            out.append(
                {
                    "id": infer_model_id(file.name),
                    "name": file.stem,
                    "path": path,
                    "size": size,
                    "sizeText": human_size(size),
                    "source": str(root),
                }
            )
        if len(out) >= limit:
            break
    return sorted(out, key=lambda item: (item["source"], item["name"].lower()))


def gpu_profile() -> dict[str, Any]:
    try:
        proc = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader,nounits"],
            text=True,
            capture_output=True,
            timeout=3,
            check=False,
        )
    except Exception as exc:
        return {"ok": False, "name": "", "vramMb": 0, "vramGb": 0, "error": str(exc)}
    if proc.returncode == 0 and proc.stdout.strip():
        first = proc.stdout.strip().splitlines()[0]
        parts = [part.strip() for part in first.split(",")]
        total_mb = parse_int(parts[-1]) or 0
        return {
            "ok": True,
            "name": ", ".join(parts[:-1]) if len(parts) > 1 else parts[0],
            "vramMb": total_mb,
            "vramGb": round(total_mb / 1024, 1) if total_mb else 0,
        }
    return {"ok": False, "name": "", "vramMb": 0, "vramGb": 0, "error": (proc.stderr or proc.stdout).strip()}


def configured_profile(models: list[dict[str, Any]]) -> dict[str, Any]:
    gpu_models = [m for m in models if not m.get("cpu")]
    contexts = [int(m.get("context") or 0) for m in gpu_models if m.get("context")]
    names = " ".join((m.get("id", "") + " " + m.get("name", "")).lower() for m in gpu_models)
    inferred_vram = 0
    if "5090" in names or "32 gb" in names or any("27b" in str(m.get("name", "")).lower() for m in gpu_models):
        inferred_vram = 32
    return {
        "gpuModelCount": len(gpu_models),
        "maxContext": max(contexts) if contexts else 0,
        "inferredVramGb": inferred_vram,
    }


def recipe(title: str, repo: str, query: str, quant: str, context: str, fit: str, why: str,
          source: str = "curated", date: str = "", family: str = "",
          estimated_vram_gb: float = 0) -> dict[str, Any]:
    """Create a cookbook recipe dict with source, family, and optional VRAM estimate."""
    return {
        "title": title,
        "repo": repo,
        "query": query,
        "quant": quant,
        "context": context,
        "fit": fit,
        "why": why,
        "source": source,
        "date": date,
        "family": family,
        "estimatedVramGb": estimated_vram_gb,
        "estimatedVramText": "",
        "vramFit": "",
        # User tracking (merged by load_cookbook / user_cookbook)
        "favorite": False,
        "tried": False,
        "lastUsed": "",
        "personalNote": "",
        "personalRating": None,
    }


def quant_multiplier(quant: str) -> float:
    """Return a multiplier for estimating VRAM from model params based on quant name."""
    q = quant.upper()
    # Exact or near-exact matches
    if "Q8_0" in q or q == "Q8":
        return 1.1
    if "Q6" in q:
        return 0.85
    if "Q5" in q:
        return 0.65
    # Q4 variants (includes IQ4, MXFP4_MOE for MoE models)
    if "Q4" in q:
        return 0.5
    if "Q3" in q:
        return 0.35
    if "Q2" in q:
        return 0.25
    # FP16/BF16 — two bytes per param + KV overhead
    if "FP16" in q or "BF16" in q:
        return 2.2
    # Fallback: default to Q4_K_M estimate
    return 0.5


def _extract_params_from_repo(repo_id: str) -> float:
    """Extract model parameter count (in billions) from a repo ID."""
    matches = re.findall(r"(\d+(?:\.\d+)?)\s*b", repo_id, flags=re.IGNORECASE)
    if matches:
        return max(float(m) for m in matches)
    return 0.0


def estimate_vram_gb(repo_id: str, quant: str) -> tuple[float, str, str]:
    """Estimate VRAM needed for a model + quant combo.

    Returns (estimated_gb, text, fit_label).
    fit_label: 'fits' | 'tight' | 'needs-swap' | 'too-large'
    """
    params_b = _extract_params_from_repo(repo_id)
    mult = quant_multiplier(quant)

    if params_b <= 0:
        return (0.0, "unknown", "unknown")

    # Model weights in GB
    vram_gb = params_b * mult

    # Add KV cache overhead for context (rough: context * 2 * 16 bytes per token for fp16 KV)
    # Simplified: context_gb = (context_tokens * 2 * 16) / (1024**3) ≈ context_tokens * 3.05e-5
    # For typical context 32k: ~1 GB, 65k: ~2 GB, 131k: ~4 GB
    # We use a rough heuristic: + context_gb
    ctx = ""
    if "8k" in quant.lower() or "4k" in quant.lower():
        ctx = "8k"
    elif "16k" in quant.lower():
        ctx = "16k"
    elif "32k" in quant.lower():
        ctx = "32k"
    elif "65k" in quant.lower():
        ctx = "65k"
    elif "98k" in quant.lower():
        ctx = "98k"
    elif "131k" in quant.lower():
        ctx = "131k"
    else:
        ctx = "32k"

    ctx_gb = 0
    try:
        ctx_tokens = int(ctx.replace("k", ""))
        ctx_gb = ctx_tokens * 2 * 16 / (1024 ** 3) * 1024  # rough: ~2 * 16 bytes/token, convert to GB
    except ValueError:
        ctx_gb = 1.0  # default 1 GB for KV

    total_gb = vram_gb + ctx_gb

    # Fit labels
    if total_gb <= 8:
        fit = "fits"
    elif total_gb <= 16:
        fit = "fits"
    elif total_gb <= 24:
        fit = "tight"
    elif total_gb <= 32:
        fit = "tight"
    elif total_gb <= 48:
        fit = "needs-swap"
    else:
        fit = "too-large"

    if total_gb < 1:
        text = f"{total_gb:.1f} GB"
    else:
        text = f"{total_gb:.0f} GB"

    return (round(total_gb, 1), text, fit)


def estimate_vram_from_hf_files(files: list[dict[str, Any]]) -> tuple[float, str, str]:
    """Estimate VRAM from HF model files.

    Uses actual file sizes when available.
    """
    total_size_bytes = 0
    for f in files:
        if isinstance(f, dict):
            total_size_bytes += int(f.get("size", 0) or 0)
        elif isinstance(f, str):
            # HF search API sometimes returns file info as strings
            pass
    if total_size_bytes <= 0:
        return (0.0, "unknown", "unknown")

    total_gb = total_size_bytes / (1024 ** 3)

    if total_gb < 1:
        text = f"{total_gb:.1f} GB"
    else:
        text = f"{total_gb:.0f} GB"

    if total_gb <= 8:
        fit = "fits"
    elif total_gb <= 16:
        fit = "fits"
    elif total_gb <= 24:
        fit = "tight"
    elif total_gb <= 32:
        fit = "tight"
    elif total_gb <= 48:
        fit = "needs-swap"
    else:
        fit = "too-large"

    return (round(total_gb, 1), text, fit)


def _vram_text(estimated_gb: float, effective_vram: float) -> str:
    """Format VRAM text with fit indicator."""
    if estimated_gb <= 0:
        return "unknown"
    base = f"{estimated_gb:.0f} GB"
    if effective_vram > 0:
        fit_icon = ""
        if estimated_gb <= effective_vram * 0.75:
            fit_icon = " ✓"
        elif estimated_gb <= effective_vram:
            fit_icon = " ~"
        elif estimated_gb <= effective_vram * 1.5:
            fit_icon = " ≈"
        else:
            fit_icon = " !!"
        return base + fit_icon
    return base


def _vram_fit_label(estimated_gb: float, effective_vram: float) -> str:
    """Return a fit label based on estimated VRAM vs effective VRAM."""
    if estimated_gb <= 0 or effective_vram <= 0:
        return "unknown"
    if estimated_gb <= effective_vram * 0.75:
        return "fits"
    elif estimated_gb <= effective_vram:
        return "fits"
    elif estimated_gb <= effective_vram * 1.5:
        return "tight"
    elif estimated_gb <= effective_vram * 2:
        return "needs-swap"
    else:
        return "too-large"


def cookbook_recipes(vram_gb: float, configured: dict[str, Any]) -> list[dict[str, Any]]:
    effective_vram = vram_gb or configured.get("inferredVramGb") or 16
    high_vram = effective_vram >= 28
    mid_vram = 16 <= effective_vram < 28
    recipes: list[dict[str, Any]] = []

    if high_vram:
        # High VRAM (>=28 GB) — dense 27B-70B, MoE, long-context
        recipes.extend([
            recipe(
                "Qwen coder family",
                "lmstudio-community/Qwen3.6-27B-GGUF",
                "lmstudio-community/Qwen3.6-27B-GGUF",
                "Q4_K_M or Q6_K",
                "65k-98k",
                "Strong fit for 32 GB VRAM; Q4_K_M leaves room for long context, Q6_K is the quality test.",
                "Reliable editor/orchestrator model when latency and code quality both matter.",
                family="qwen",
                estimated_vram_gb=14.0,
            ),
            recipe(
                "Qwen MoE reasoning family",
                "unsloth/Qwen3.6-35B-A3B-GGUF",
                "unsloth/Qwen3.6-35B-A3B-GGUF Q4",
                "Q4_K_M, IQ4_NL, or MXFP4_MOE",
                "65k-131k",
                "MoE model: larger total capacity while active parameters stay lower than dense 35B.",
                "Planning, reviews, and hard multi-step changes.",
                family="qwen",
                estimated_vram_gb=6.0,
            ),
            recipe(
                "Codestral coding family",
                "mistral-community/Codestral-22B-GGUF",
                "mistral-community/Codestral-22B-GGUF Q4_K_M",
                "Q4_K_M or Q5_K_M",
                "32k-65k",
                "Mistral's strongest code model; good alternative to Qwen for coding tasks.",
                "Code generation, review, and coding-adjacent work.",
                family="codestral",
                estimated_vram_gb=12.0,
            ),
            recipe(
                "Command R+ long-context",
                "bartowski/Command-R-plus-GGUF",
                "bartowski/Command-R-plus-GGUF Q4_K_M",
                "Q4_K_M",
                "131k",
                "Command R+ supports 131k context; excellent for RAG and long-document work.",
                "Long-context, RAG-friendly tasks and document analysis.",
                family="command",
                estimated_vram_gb=14.0,
            ),
            recipe(
                "Llama general family",
                "Search: Llama GGUF",
                "Llama 3.3 70B GGUF Q4_K_M",
                "Q3_K_M, Q4_K_M, or IQ4",
                "32k-65k",
                "Large Llama-class models are plausible on 32 GB with careful quant/context choices.",
                "General chat, writing, broad instruction following, and compatibility testing.",
                family="llama",
                estimated_vram_gb=42.0,
            ),
            recipe(
                "Mistral / Mixtral family",
                "Search: Mistral GGUF",
                "Mistral Small Instruct GGUF Q4_K_M",
                "Q4_K_M or Q5_K_M",
                "32k-65k",
                "Good alternative family to Qwen for general work and coding-adjacent tasks.",
                "Cross-checking outputs and keeping a non-Qwen fallback.",
                family="mistral",
                estimated_vram_gb=12.0,
            ),
            recipe(
                "DeepSeek family",
                "Search: DeepSeek GGUF",
                "DeepSeek Coder GGUF Q4_K_M",
                "Q4_K_M or Q5_K_M",
                "32k-65k",
                "Worth browsing for code-heavy and reasoning-heavy variants.",
                "Specialized coding, refactor planning, and comparative testing.",
                family="deepseek",
                estimated_vram_gb=14.0,
            ),
            recipe(
                "Gemma family",
                "ggml-org/gemma-3-4b-it-qat-GGUF",
                "Gemma 3 GGUF QAT Q4",
                "Q4_0, Q4_K_M, or Q8_0 depending size",
                "8k-32k",
                "Smaller Gemma variants are fast and already present in your cache.",
                "Lightweight local assistant, fallback, and quick tasks.",
                family="gemma",
                estimated_vram_gb=2.5,
            ),
            recipe(
                "Phi family",
                "Search: Phi GGUF",
                "Phi 4 GGUF Q4_K_M",
                "Q4_K_M or Q6_K",
                "16k-32k",
                "Small-to-mid Microsoft models can be efficient local utility models.",
                "Fast assistants, constrained tasks, and low-latency routing.",
                family="phi",
                estimated_vram_gb=6.0,
            ),
            recipe(
                "Grok family",
                "Search: Grok GGUF",
                "Grok-1 GGUF Q4_K_M",
                "Q4_K_M or Q3_K_M",
                "8k-32k",
                "Large xAI model; good for testing and comparison.",
                "Experimental use, comparison with other families.",
                family="grok",
                estimated_vram_gb=36.0,
            ),
            recipe(
                "Vision family",
                "Search: vision GGUF mmproj",
                "GGUF vision mmproj Q4_K_M",
                "Q4_K_M plus mmproj",
                "16k-49k",
                "Look for repos with an mmproj file and keep context below text-only profiles.",
                "Screenshots, UI inspection, diagrams, and local visual analysis.",
                family="vision",
                estimated_vram_gb=8.0,
            ),
            recipe(
                "Audio family",
                "Search: audio whisper gguf",
                "Whisper GGUF Q4",
                "Q4_K_M or Q5_K_M",
                "8k-49k",
                "Speech-to-text models for audio processing.",
                "Audio transcription and speech recognition.",
                family="audio",
                estimated_vram_gb=2.0,
            ),
        ])
    elif mid_vram:
        # Mid VRAM (16-27 GB) — dense 9B-14B, some 27B
        recipes.extend([
            recipe(
                "9B-14B balanced coder",
                "Search: 9B 14B coder GGUF",
                "coder 9B 14B GGUF Q5_K_M",
                "Q5_K_M or Q6_K",
                "32k-65k",
                "Good target for 16-24 GB VRAM with enough room for useful context.",
                "Primary coding model when dense 27B is too tight.",
                family="qwen",
                estimated_vram_gb=8.0,
            ),
            recipe(
                "Starcoder2 code family",
                "lmstudio-community/starcoder2-15b-GGUF",
                "lmstudio-community/starcoder2-15b-GGUF Q4_K_M",
                "Q4_K_M or Q5_K_M",
                "16k-32k",
                "Code-specific model from BigCode; strong but heavier than 9B.",
                "Code generation and specialized coding tasks.",
                family="starcoder",
                estimated_vram_gb=8.0,
            ),
            recipe(
                "Gemma / Phi utility",
                "Search: Gemma Phi GGUF",
                "Gemma Phi GGUF Q6_K",
                "Q6_K or Q8_0",
                "16k-32k",
                "Small enough to keep responsive while other workloads run.",
                "Shell help, quick edits, and lightweight subagents.",
                family="gemma",
                estimated_vram_gb=6.0,
            ),
            recipe(
                "Llama 8B class",
                "Search: Llama 8B GGUF",
                "Llama 8B Instruct GGUF Q6_K",
                "Q5_K_M, Q6_K, or Q8_0",
                "16k-32k",
                "Fits comfortably on midrange GPUs.",
                "General fallback and compatibility testing.",
                family="llama",
                estimated_vram_gb=6.0,
            ),
            recipe(
                "Mistral 7B class",
                "Search: Mistral 7B GGUF",
                "Mistral 7B Instruct GGUF Q6_K",
                "Q5_K_M, Q6_K, or Q8_0",
                "16k-32k",
                "Efficient and commonly available in GGUF.",
                "Fast non-Qwen assistant and routing fallback.",
                family="mistral",
                estimated_vram_gb=6.0,
            ),
            recipe(
                "Yi family",
                "lmstudio-community/Yi-34B-GGUF",
                "lmstudio-community/Yi-34B-GGUF Q4_K_M",
                "Q4_K_M or Q3_K_M",
                "4k-16k",
                "Quality testing and comparison; larger but fits with low context.",
                "Model comparison and quality testing.",
                family="yi",
                estimated_vram_gb=18.0,
            ),
        ])
    else:
        # Low VRAM (<16 GB) — compact models, fast fallback
        recipes.extend([
            recipe(
                "Qwen 2.5 small family",
                "Qwen/Qwen2.5-1.5B-Instruct-GGUF",
                "Qwen2.5-1.5B-Instruct GGUF Q8_0",
                "Q6_K or Q8_0",
                "8k-32k",
                "Fastest coding option on weak hardware; Q8_0 preserves quality.",
                "Fast coding fallback and lightweight subagent.",
                family="qwen",
                estimated_vram_gb=1.8,
            ),
            recipe(
                "SmolLM ultra-compact family",
                "HuggingFaceTB/SmolLM2-1.7B-GGUF",
                "HuggingFaceTB/SmolLM2-1.7B-GGUF Q8_0",
                "Q6_K or Q8_0",
                "4k-8k",
                "Ultra-compact Microsoft model; fits anywhere.",
                "Ultra-fast local fallback and simple tasks.",
                family="gemma",
                estimated_vram_gb=1.8,
            ),
            recipe(
                "Compact general chat",
                "ggml-org/gemma-3-4b-it-qat-GGUF",
                "ggml-org/gemma-3-4b-it-qat-GGUF Q4",
                "Q4_0",
                "8k-32k",
                "Small, practical, and already present in your Hugging Face cache.",
                "General local assistant and quick non-coding tasks.",
                family="gemma",
                estimated_vram_gb=2.5,
            ),
            recipe(
                "Phi-3.5 Mini",
                "microsoft/Phi-3.5-mini-instruct-GGUF",
                "microsoft/Phi-3.5-mini-instruct-GGUF Q6_K",
                "Q6_K or Q8_0",
                "4k-16k",
                "Microsoft's compact 3.8B model; efficient for constrained setups.",
                "Quick tasks, shell help, and lightweight subagent.",
                family="phi",
                estimated_vram_gb=3.8,
            ),
            recipe(
                "1B-3B coding fallback",
                "Search: 1.5B 3B coder GGUF",
                "1.5B 3B coder GGUF Q8_0",
                "Q6_K or Q8_0",
                "8k-32k",
                "Works on low VRAM and CPU fallback setups.",
                "Fast routing fallback while larger GPU models are unavailable.",
                family="qwen",
                estimated_vram_gb=3.0,
            ),
            recipe(
                "Tiny Llama / Phi class",
                "Search: tiny llama phi GGUF",
                "tiny llama phi GGUF Q8_0",
                "Q6_K or Q8_0",
                "4k-16k",
                "Best for CPU and very small VRAM profiles.",
                "Simple utility tasks and health-check fallback.",
                family="phi",
                estimated_vram_gb=2.0,
            ),
        ])
    return recipes


def model_family(repo_id: str) -> str:
    text = repo_id.lower()
    for name in ["qwen", "llama", "mistral", "mixtral", "deepseek", "gemma", "phi", "glm", "yi", "minicpm", "codestral", "starcoder", "command"]:
        if name in text:
            return name
    return repo_id.split("/", 1)[0].lower()


def estimated_params_b(repo_id: str) -> float:
    matches = re.findall(r"(\d+(?:\.\d+)?)\s*b", repo_id, flags=re.IGNORECASE)
    return max((float(item) for item in matches), default=0.0)


def catalog_fit(repo_id: str, vram_gb: float) -> tuple[str, str, str]:
    params = estimated_params_b(repo_id)
    lower = repo_id.lower()
    if not params:
        return ("Inspect files", "unknown", "No size is obvious from the repo name; open files before downloading.")
    if params <= 4:
        return ("Q6_K or Q8_0", "8k-32k", "Small model; should be fast on this system.")
    if params <= 9:
        return ("Q5_K_M, Q6_K, or Q8_0", "16k-65k", "Comfortable fit; use higher quant if quality matters.")
    if params <= 14:
        return ("Q4_K_M or Q5_K_M", "32k-65k", "Good mid-size candidate with practical context.")
    if params <= 32:
        return ("Q4_K_M or IQ4", "32k-98k", "Large model; appropriate for your inferred 32 GB profile.")
    if params <= 72 and vram_gb >= 28:
        if "moe" in lower or "a3b" in lower:
            return ("Q4_K_M, IQ4, or MXFP4", "32k-131k", "Large MoE candidate; check active-parameter and shard details.")
        return ("Q2_K, Q3_K_M, or IQ4", "16k-32k", "Very large dense candidate; treat as experimental on 32 GB.")
    return ("smaller quant", "limited", "Likely too large unless heavily quantized or partially offloaded.")


def hf_catalog_recipes(vram_gb: float, limit: int = 80) -> list[dict[str, Any]]:
    searches = ["GGUF", "Llama GGUF", "Mistral GGUF", "DeepSeek GGUF", "Gemma GGUF", "Phi GGUF", "GLM GGUF", "vision GGUF"]
    seen: set[str] = set()
    out: list[dict[str, Any]] = []
    for term in searches:
        try:
            rows = hf_search(term, limit=20)
        except Exception:
            continue
        for row in rows:
            repo_id = str(row.get("id") or "")
            if not repo_id or repo_id in seen:
                continue
            seen.add(repo_id)
            quant, context, fit = catalog_fit(repo_id, vram_gb)
            downloads = row.get("downloads", 0)
            likes = row.get("likes", 0)
            last_modified = row.get("lastModified", "")
            # Estimate VRAM from HF file sizes when available
            files = row.get("files", [])
            vram_gb_est, vram_text, vram_fit_label = estimate_vram_from_hf_files(files)
            if vram_gb_est <= 0:
                # Fall back to estimation from repo name
                vram_gb_est, vram_text, vram_fit_label = estimate_vram_gb(repo_id, quant)
            out.append(
                recipe(
                    f"{model_family(repo_id).title()}: {repo_id.split('/')[-1].replace('-GGUF', '')}",
                    repo_id,
                    repo_id,
                    quant,
                    context,
                    fit,
                    f"Live Hugging Face GGUF catalog entry. Downloads: {downloads}; likes: {likes}.",
                    source="huggingface",
                    date=last_modified[:10] if last_modified else "",
                    family=model_family(repo_id),
                    estimated_vram_gb=vram_gb_est,
                )
            )
            if len(out) >= limit:
                return out
    return out


def load_cookbook() -> dict[str, Any]:
    try:
        _, llama_data = load_llama_yaml()
        models = normalized_models(llama_data)
    except Exception:
        models = []
    gpu = gpu_profile()
    configured = configured_profile(models)
    vram = float(gpu.get("vramGb") or configured.get("inferredVramGb") or 0)
    recipes = cookbook_recipes(vram, configured) + hf_catalog_recipes(vram or 16)
    # Format VRAM text with fit indicators for each recipe
    effective_vram = vram or 16
    for r in recipes:
        est = r.get("estimatedVramGb", 0)
        if est > 0:
            r["estimatedVramText"] = _vram_text(est, effective_vram)
            r["vramFit"] = _vram_fit_label(est, effective_vram)
    return {
        "ok": True,
        "system": {
            "gpu": gpu,
            "configured": configured,
            "basis": "nvidia-smi" if gpu.get("ok") else "router config fallback",
            "effectiveVramGb": vram or 16,
        },
        "recipes": recipes,
    }


# ─── User cookbook persistence ───────────────────────────────────────────────

USER_COOKBOOK_DIR = HOME / ".config" / "llm-manager"
USER_COOKBOOK_PATH = USER_COOKBOOK_DIR / "user-cookbook.json"

_DEFAULT_USER_COOKBOOK = {
    "version": 1,
    "lastUpdated": "",
    "recipes": {},
    "customRecipes": [],
}


def load_user_cookbook() -> dict[str, Any]:
    """Load user's cookbook state. Returns defaults if file missing or invalid."""
    try:
        data = read_json(USER_COOKBOOK_PATH, None)
        if isinstance(data, dict) and data.get("version") == 1:
            # Merge missing keys
            for key, default in _DEFAULT_USER_COOKBOOK.items():
                if key not in data:
                    data[key] = default
            return data
    except Exception:
        pass
    return dict(_DEFAULT_USER_COOKBOOK)


def save_user_cookbook(data: dict[str, Any]) -> bool:
    """Atomically save user cookbook. Returns True on success."""
    try:
        data["lastUpdated"] = datetime.now().strftime("%Y-%m-%dT%H:%M:%SZ")
        write_json_atomic(USER_COOKBOOK_PATH, data)
        return True
    except Exception as exc:
        print(f"Warning: could not save user cookbook: {exc}", file=sys.stderr)
        return False


def _merge_user_state(recipes: list[dict[str, Any]], user_data: dict[str, Any]) -> list[dict[str, Any]]:
    """Merge user tracking state into recipes based on repo_id."""
    user_recipes = user_data.get("recipes", {})
    custom = user_data.get("customRecipes", [])
    merged = []
    repo_set = set()
    for r in recipes:
        repo_id = r.get("repo", "")
        repo_set.add(repo_id)
        state = user_recipes.get(repo_id, {})
        r["favorite"] = bool(state.get("favorite", False))
        r["tried"] = bool(state.get("tried", False))
        r["lastUsed"] = state.get("lastUsed", "")
        r["personalNote"] = str(state.get("personalNote", "") or "")
        r["personalRating"] = state.get("personalRating")
        merged.append(r)
    # Also add custom recipes from user
    for cr in custom:
        merged.append(dict(cr))
    return merged


def load_cookbook() -> dict[str, Any]:
    """Load cookbook and merge user state."""
    try:
        _, llama_data = load_llama_yaml()
        models = normalized_models(llama_data)
    except Exception:
        models = []
    gpu = gpu_profile()
    configured = configured_profile(models)
    vram = float(gpu.get("vramGb") or configured.get("inferredVramGb") or 0)
    recipes = cookbook_recipes(vram, configured) + hf_catalog_recipes(vram or 16)
    # Merge user state
    user_data = load_user_cookbook()
    recipes = _merge_user_state(recipes, user_data)
    # Format VRAM text with fit indicators for each recipe
    effective_vram = vram or 16
    for r in recipes:
        est = r.get("estimatedVramGb", 0)
        if est > 0:
            r["estimatedVramText"] = _vram_text(est, effective_vram)
            r["vramFit"] = _vram_fit_label(est, effective_vram)
    return {
        "ok": True,
        "system": {
            "gpu": gpu,
            "configured": configured,
            "basis": "nvidia-smi" if gpu.get("ok") else "router config fallback",
            "effectiveVramGb": vram or 16,
        },
        "recipes": recipes,
    }


def search_recipes(query: str, source_filter: str = "all") -> list[dict[str, Any]]:
    """Search recipes by query string, optionally filtered by source.

    Searches across: title, repo, family, quant, context, fit, why, personalNote, vramText.
    source_filter: 'all', 'curated', 'huggingface'
    """
    if not query or not query.strip():
        return load_cookbook().get("recipes", [])

    query_lower = query.lower().strip()
    results = load_cookbook().get("recipes", [])
    filtered: list[dict[str, Any]] = []

    for r in results:
        # Apply source filter
        src = r.get("source", "curated")
        if source_filter != "all" and src != source_filter:
            continue

        # Search across multiple fields
        searchable = " ".join([
            str(r.get("title", "") or ""),
            str(r.get("repo", "") or ""),
            str(r.get("family", "") or ""),
            str(r.get("quant", "") or ""),
            str(r.get("context", "") or ""),
            str(r.get("fit", "") or ""),
            str(r.get("why", "") or ""),
            str(r.get("estimatedVramText", "") or ""),
            str(r.get("personalNote", "") or ""),
            str(r.get("date", "") or ""),
        ]).lower()

        if query_lower in searchable:
            filtered.append(r)

    return filtered


def set_recipe_favorite(repo_id: str, favorite: bool) -> dict[str, Any]:
    """Set favorite flag for a recipe by repo_id."""
    user_data = load_user_cookbook()
    if repo_id not in user_data["recipes"]:
        user_data["recipes"][repo_id] = {}
    user_data["recipes"][repo_id]["favorite"] = favorite
    if save_user_cookbook(user_data):
        return {"ok": True, "repo": repo_id, "favorite": favorite}
    return {"ok": False, "error": "Failed to save user cookbook"}


def set_recipe_tried(repo_id: str, tried: bool) -> dict[str, Any]:
    """Set tried flag for a recipe by repo_id."""
    user_data = load_user_cookbook()
    if repo_id not in user_data["recipes"]:
        user_data["recipes"][repo_id] = {}
    user_data["recipes"][repo_id]["tried"] = tried
    if tried:
        user_data["recipes"][repo_id]["lastUsed"] = datetime.now().strftime("%Y-%m-%d")
    else:
        user_data["recipes"][repo_id].pop("lastUsed", None)
    if save_user_cookbook(user_data):
        return {"ok": True, "repo": repo_id, "tried": tried}
    return {"ok": False, "error": "Failed to save user cookbook"}


def set_recipe_note(repo_id: str, note: str) -> dict[str, Any]:
    """Set personal note for a recipe by repo_id."""
    user_data = load_user_cookbook()
    if repo_id not in user_data["recipes"]:
        user_data["recipes"][repo_id] = {}
    user_data["recipes"][repo_id]["personalNote"] = note
    if save_user_cookbook(user_data):
        return {"ok": True, "repo": repo_id, "note": note}
    return {"ok": False, "error": "Failed to save user cookbook"}


def set_recipe_rating(repo_id: str, rating: int) -> dict[str, Any]:
    """Set personal rating (1-5) for a recipe by repo_id."""
    user_data = load_user_cookbook()
    if repo_id not in user_data["recipes"]:
        user_data["recipes"][repo_id] = {}
    if 1 <= rating <= 5:
        user_data["recipes"][repo_id]["personalRating"] = rating
    else:
        user_data["recipes"][repo_id].pop("personalRating", None)
    if save_user_cookbook(user_data):
        return {"ok": True, "repo": repo_id, "rating": rating}
    return {"ok": False, "error": "Failed to save user cookbook"}


def add_custom_recipe(recipe_data: dict[str, Any]) -> dict[str, Any]:
    """Add a custom recipe to the user cookbook."""
    user_data = load_user_cookbook()
    if "customRecipes" not in user_data:
        user_data["customRecipes"] = []
    # Ensure required fields
    if "repo" not in recipe_data:
        return {"ok": False, "error": "Custom recipe needs a 'repo' field"}
    user_data["customRecipes"].append(recipe_data)
    if save_user_cookbook(user_data):
        return {"ok": True, "recipe": recipe_data}
    return {"ok": False, "error": "Failed to save user cookbook"}


def remove_custom_recipe(repo_id: str) -> dict[str, Any]:
    """Remove a custom recipe from the user cookbook."""
    user_data = load_user_cookbook()
    original_len = len(user_data.get("customRecipes", []))
    user_data["customRecipes"] = [r for r in user_data.get("customRecipes", []) if r.get("repo") != repo_id]
    if len(user_data["customRecipes"]) < original_len:
        if save_user_cookbook(user_data):
            return {"ok": True, "removed": repo_id}
    return {"ok": False, "error": "Recipe not found or save failed"}


def hf_request(path: str, query: dict[str, str] | None = None) -> Any:
    url = "https://huggingface.co" + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    req = urllib.request.Request(url, headers={"User-Agent": "quickshell-llm-manager/1.0"})
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode("utf-8"))


def hf_search(search: str, limit: int = 20) -> list[dict[str, Any]]:
    data = hf_request(
        "/api/models",
        {
            "search": search or "GGUF",
            "filter": "gguf",
            "sort": "downloads",
            "direction": "-1",
            "limit": str(limit),
            "full": "true",
        },
    )
    out: list[dict[str, Any]] = []
    for item in data if isinstance(data, list) else []:
        siblings = item.get("siblings") or []
        ggufs = [s.get("rfilename", "") for s in siblings if str(s.get("rfilename", "")).lower().endswith(".gguf")]
        out.append(
            {
                "id": item.get("id", ""),
                "author": item.get("author", ""),
                "downloads": item.get("downloads", 0),
                "likes": item.get("likes", 0),
                "lastModified": item.get("lastModified", ""),
                "tags": item.get("tags", [])[:12],
                "pipeline_tag": item.get("pipeline_tag", ""),
                "ggufCount": len(ggufs),
                "files": ggufs[:12],
            }
        )
    return out


def hf_model_files(repo_id: str) -> list[dict[str, Any]]:
    data = hf_request("/api/models/" + urllib.parse.quote(repo_id, safe="/"))
    siblings = data.get("siblings") or []
    files = []
    shard_groups: dict[str, list[dict[str, Any]]] = {}
    for sibling in siblings:
        name = str(sibling.get("rfilename", ""))
        if not is_main_gguf(Path(name)):
            continue
        size = int(sibling.get("size") or 0)
        match = re.match(r"^(.*)-00001-of-(\d+)\.gguf$", name)
        any_shard = re.match(r"^(.*)-\d{5}-of-\d+\.gguf$", name)
        if any_shard:
            shard_groups.setdefault(any_shard.group(1), []).append({"name": name, "size": size})
        elif match:
            shard_groups.setdefault(match.group(1), []).append({"name": name, "size": size})
        else:
            files.append({"name": name, "size": size, "sizeText": human_size(size) if size else "unknown", "sharded": False})
    for _, group in shard_groups.items():
        group = sorted(group, key=lambda item: item["name"])
        first = group[0]
        total_size = sum(int(item.get("size") or 0) for item in group)
        files.append(
            {
                "name": first["name"],
                "size": total_size,
                "sizeText": f"{len(group)} shards, {human_size(total_size)}" if total_size else f"{len(group)} shards",
                "sharded": True,
                "shards": [item["name"] for item in group],
            }
        )
    return sorted(files, key=lambda item: item["name"].lower())


def model_path_for_cmd(path: Path, llama_data: Any) -> str:
    macros = llama_data.get("macros", {}) if isinstance(llama_data, dict) else {}
    path_str = str(path)
    best_key = ""
    best_value = ""
    for key, value in macros.items():
        value_str = str(value)
        if path_str.startswith(value_str.rstrip("/") + "/") and len(value_str) > len(best_value):
            best_key = str(key)
            best_value = value_str.rstrip("/")
    if best_key:
        return "${" + best_key + "}/" + os.path.relpath(path_str, best_value)
    return path_str


def llama_binary_for_cmd(llama_data: Any) -> str:
    macros = llama_data.get("macros", {}) if isinstance(llama_data, dict) else {}
    if "llama" in macros:
        return "${llama}"
    for candidate in [
        HOME / "work/llm/llama.cpp/build/bin/llama-server",
        Path("/usr/bin/llama-server"),
        Path("/usr/local/bin/llama-server"),
    ]:
        if candidate.exists():
            return str(candidate)
    return "llama-server"


def default_llama_cmd(model_path: Path, llama_data: Any, context: int = 65536, output: int = 8192) -> str:
    model_ref = model_path_for_cmd(model_path, llama_data)
    return "\n".join(
        [
            llama_binary_for_cmd(llama_data),
            "  --port ${PORT}",
            f"  -m {shlex.quote(model_ref)}",
            "  -ngl 999",
            f"  -c {int(context)}",
            "  -np 1",
            f"  -n {int(output)}",
            "  -b 4096",
            "  -ub 1024",
            "  --cache-type-k q8_0",
            "  --cache-type-v q8_0",
            "  -fa auto",
            "  --jinja",
            "  --no-warmup",
            "  --defrag-thold 0.1",
            "  --api-key ${env.LLAMA_API_KEY}",
        ]
    )


def add_model_to_router(path: str, model_id: str = "", name: str = "", description: str = "", context: int = 65536) -> dict[str, Any]:
    model_path = Path(path).expanduser()
    if not model_path.exists():
        raise RuntimeError(f"Model file does not exist: {model_path}")
    yaml, llama_data = load_llama_yaml()
    models = llama_data.setdefault("models", {})
    existing = {str(key) for key in models.keys()}
    model_id = unique_model_id(model_id or model_path.name, existing)
    backups = []
    for config_path in [LLAMA_CONFIG, OPENCODE_CONFIG, PI_MODELS, PI_SETTINGS]:
        made = backup(config_path)
        if made:
            backups.append(made)
    models[model_id] = {
        "name": name or model_path.stem,
        "description": description or "Added from Quickshell LLM Manager",
        "ttl": llama_data.get("ttl", 600),
        "cmd": default_llama_cmd(model_path, llama_data, context=context),
    }
    dump_llama_yaml(yaml, llama_data)
    normalized = normalized_models(llama_data)
    sync_provider_models(normalized)
    return {"ok": True, "model": model_id, "backups": backups}


def sync_provider_models(models: list[dict[str, Any]]) -> None:
    opencode = read_json(OPENCODE_CONFIG, {})
    provider = opencode.setdefault("provider", {}).setdefault("llamaswap", {})
    provider["models"] = provider_model_entries(models, include_aliases=True)
    write_json_atomic(OPENCODE_CONFIG, opencode)

    pi_models = read_json(PI_MODELS, {})
    pi_provider = pi_models.setdefault("providers", {}).setdefault("llamaswap", {})
    pi_provider["models"] = pi_model_list(models)
    write_json_atomic(PI_MODELS, pi_models)


def download_hf_model(repo_id: str, filename: str, model_id: str = "", name: str = "", context: int = 65536) -> dict[str, Any]:
    if not repo_id or not filename:
        raise RuntimeError("download requires repo_id and filename")
    files = hf_model_files(repo_id)
    selected = next((item for item in files if item.get("name") == filename), {"name": filename, "shards": [filename]})
    download_files = selected.get("shards") or [filename]
    dest_dir = DEFAULT_MODEL_DIR / repo_id.replace("/", "__")
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / Path(filename).name
    hf_cli = shutil.which("hf")
    if hf_cli:
        for item in download_files:
            proc = subprocess.run(
                [hf_cli, "download", repo_id, str(item), "--local-dir", str(dest_dir)],
                text=True,
                capture_output=True,
                check=False,
            )
            if proc.returncode != 0:
                raise RuntimeError((proc.stderr or proc.stdout or "hf download failed").strip())
            downloaded = dest_dir / str(item)
            final = dest_dir / Path(str(item)).name
            if downloaded.exists() and downloaded != final:
                final.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(downloaded), str(final))
    else:
        for item in download_files:
            final = dest_dir / Path(str(item)).name
            url = f"https://huggingface.co/{repo_id}/resolve/main/{urllib.parse.quote(str(item), safe='/')}?download=1"
            req = urllib.request.Request(url, headers={"User-Agent": "quickshell-llm-manager/1.0"})
            with urllib.request.urlopen(req, timeout=60) as resp, final.open("wb") as fh:
                shutil.copyfileobj(resp, fh)
    result = add_model_to_router(
        str(dest),
        model_id=model_id or infer_model_id(filename),
        name=name or Path(filename).stem,
        description=f"Downloaded from Hugging Face: {repo_id}",
        context=context,
    )
    result["path"] = str(dest)
    return result


def parse_frontmatter(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        return {"path": str(path), "frontmatter": {}, "body": text}
    end = text.find("\n---", 4)
    if end == -1:
        return {"path": str(path), "frontmatter": {}, "body": text}
    raw = text[4:end]
    body = text[end + 4 :].lstrip("\n")
    yaml = need_ruamel()
    parse_error = ""
    try:
        data = yaml.load(raw) or {}
    except Exception as exc:
        data = forgiving_frontmatter(raw)
        parse_error = str(exc)
    return {
        "path": str(path),
        "frontmatter": dict(data),
        "frontmatterRaw": raw,
        "frontmatterParseError": parse_error,
        "body": body,
    }


def forgiving_frontmatter(raw: str) -> dict[str, Any]:
    data: dict[str, Any] = {}
    for line in raw.splitlines():
        if line.startswith(" ") or line.startswith("\t"):
            continue
        match = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if not match:
            continue
        key, value = match.group(1), match.group(2)
        if value in {"true", "false"}:
            data[key] = value == "true"
        else:
            data[key] = value.strip().strip("\"'")
    return data


def dump_frontmatter(agent: dict[str, Any]) -> str:
    from io import StringIO

    raw = agent.get("frontmatterRaw")
    if raw:
        body = str(agent.get("body") or "")
        if body and not body.endswith("\n"):
            body += "\n"
        return f"---\n{update_raw_frontmatter(str(raw), agent.get('frontmatter') or {})}---\n\n{body}"

    yaml = need_ruamel()
    buf = StringIO()
    yaml.dump(agent.get("frontmatter") or {}, buf)
    body = str(agent.get("body") or "")
    if body and not body.endswith("\n"):
        body += "\n"
    return f"---\n{buf.getvalue()}---\n\n{body}"


def update_raw_frontmatter(raw: str, updates: dict[str, Any]) -> str:
    lines = raw.splitlines()
    keys = ["name", "description", "mode", "model"]
    seen: set[str] = set()
    out: list[str] = []
    for line in lines:
        replaced = False
        for key in keys:
            if re.match(rf"^{re.escape(key)}:\s*", line):
                out.append(f"{key}: {frontmatter_scalar(updates.get(key, ''))}")
                seen.add(key)
                replaced = True
                break
        if not replaced:
            out.append(line)
    insert_at = 0
    for key in keys:
        if key in updates and key not in seen and updates.get(key) not in ("", None):
            out.insert(insert_at, f"{key}: {frontmatter_scalar(updates[key])}")
            insert_at += 1
    return "\n".join(out) + "\n"


def frontmatter_scalar(value: Any) -> str:
    text = str(value)
    if text == "":
        return "\"\""
    if re.search(r"[:#\[\]{}]|^\s|\s$", text):
        return json.dumps(text, ensure_ascii=False)
    return text


def load_agents(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    agents = []
    for file in sorted(path.glob("*.md")):
        parsed = parse_frontmatter(file)
        fm = parsed["frontmatter"]
        agents.append(
            {
                "file": str(file),
                "id": str(fm.get("name") or file.stem),
                "description": str(fm.get("description", "")),
                "model": str(fm.get("model", "")),
                "mode": str(fm.get("mode", "")),
                "frontmatter": fm,
                "frontmatterRaw": parsed.get("frontmatterRaw", ""),
                "frontmatterParseError": parsed.get("frontmatterParseError", ""),
                "body": parsed["body"],
            }
        )
    return agents


def provider_model_entries(models: list[dict[str, Any]], include_aliases: bool) -> dict[str, Any]:
    entries: dict[str, Any] = {}
    for model in models:
        if model.get("cpu"):
            continue
        model_id = model["id"]
        entries[model_id] = model_entry(model, model_id)
        if include_aliases:
            for alias in model.get("aliases", []):
                entry = model_entry(model, alias)
                effort = alias_effort(alias)
                if effort:
                    entry["name"] = f"{entry['name']} ({effort} effort)"
                entries[alias] = entry
    return entries


def model_entry(model: dict[str, Any], model_id: str) -> dict[str, Any]:
    entry: dict[str, Any] = {"name": model.get("name") or model_id}
    if model.get("vision"):
        entry["attachment"] = True
        entry["modalities"] = {"input": ["text", "image"]}
    limit: dict[str, int] = {}
    if model.get("context"):
        limit["context"] = int(model["context"])
    if model.get("output"):
        limit["output"] = int(model["output"])
    if limit:
        entry["limit"] = limit
    return entry


def pi_model_list(models: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out = []
    for model in models:
        if model.get("cpu"):
            continue
        entry = {
            "id": model["id"],
            "name": model.get("name") or model["id"],
            "contextWindow": model.get("context") or 0,
            "maxTokens": model.get("output") or 8192,
        }
        if model.get("vision"):
            entry["input"] = ["text", "image"]
        if model.get("reasoning"):
            entry["reasoning"] = True
        out.append(entry)
    return out


def load_state() -> dict[str, Any]:
    warnings: list[str] = []
    errors: list[str] = []
    try:
        _, llama_data = load_llama_yaml()
        models = normalized_models(llama_data)
    except Exception as exc:
        llama_data = {}
        models = []
        errors.append(str(exc))

    opencode = read_json(OPENCODE_CONFIG, {})
    pi_models = read_json(PI_MODELS, {})
    pi_settings = read_json(PI_SETTINGS, {})
    state = {
        "paths": {
            "llama": str(LLAMA_CONFIG),
            "opencode": str(OPENCODE_CONFIG),
            "opencodeAgents": str(OPENCODE_AGENTS),
            "piModels": str(PI_MODELS),
            "piSettings": str(PI_SETTINGS),
            "piAgents": str(PI_AGENTS),
        },
        "llama": {
            "healthCheckTimeout": llama_data.get("healthCheckTimeout", ""),
            "logLevel": llama_data.get("logLevel", ""),
            "ttl": llama_data.get("ttl", ""),
            "models": models,
        },
        "opencode": {
            "model": opencode.get("model", ""),
            "small_model": opencode.get("small_model", ""),
            "default_agent": opencode.get("default_agent", ""),
            "agents": sorted(
                [
                    {"id": key, **(value if isinstance(value, dict) else {})}
                    for key, value in (opencode.get("agent") or {}).items()
                ],
                key=lambda x: x["id"],
            ),
            "agentFiles": load_agents(OPENCODE_AGENTS),
        },
        "pi": {
            "defaultProvider": pi_settings.get("defaultProvider", ""),
            "defaultModel": pi_settings.get("defaultModel", ""),
            "defaultThinkingLevel": pi_settings.get("defaultThinkingLevel", ""),
            "enabledModels": pi_settings.get("enabledModels", []),
            "agents": load_agents(PI_AGENTS),
            "providerModels": ((pi_models.get("providers") or {}).get("llamaswap") or {}).get("models", []),
        },
        "runtime": runtime_status(),
        "validation": {"errors": errors, "warnings": warnings},
    }
    state["validation"] = validate_state(state)
    return state


def validate_model_ref(ref: str, model_ids: set[str], errors: list[str], owner: str) -> None:
    if not ref:
        return
    if "/" in ref:
        provider, model = ref.split("/", 1)
        if provider != "llamaswap":
            return
    else:
        model = ref
    if model not in model_ids:
        errors.append(f"{owner} references unknown llama-swap model '{ref}'")


def validate_state(state: dict[str, Any]) -> dict[str, list[str]]:
    errors = list((state.get("validation") or {}).get("errors") or [])
    warnings = list((state.get("validation") or {}).get("warnings") or [])
    models = state.get("llama", {}).get("models", [])
    ids = [m.get("id") for m in models]
    model_ids = set()
    for model in models:
        model_id = str(model.get("id") or "")
        if not model_id:
            errors.append("Model ID cannot be empty")
            continue
        if model_id in model_ids:
            errors.append(f"Duplicate model ID '{model_id}'")
        model_ids.add(model_id)
        for alias in model.get("aliases") or []:
            model_ids.add(str(alias))
        if not model.get("cmd"):
            errors.append(f"Model '{model_id}' has an empty command")
    if len(ids) != len(set(ids)):
        errors.append("Duplicate model IDs exist")

    validate_model_ref(str(state.get("opencode", {}).get("model", "")), model_ids, errors, "opencode.model")
    validate_model_ref(str(state.get("opencode", {}).get("small_model", "")), model_ids, errors, "opencode.small_model")
    validate_model_ref(
        str(state.get("pi", {}).get("defaultModel", "")),
        model_ids,
        errors,
        "pi.defaultModel",
    )
    for agent in state.get("opencode", {}).get("agentFiles", []):
        validate_model_ref(str(agent.get("model", "")), model_ids, errors, f"opencode agent {agent.get('id')}")
    validate_agents(state.get("opencode", {}).get("agentFiles", []), "opencode", errors)
    for agent in state.get("pi", {}).get("agents", []):
        validate_model_ref(str(agent.get("model", "")), model_ids, errors, f"pi agent {agent.get('id')}")
    validate_agents(state.get("pi", {}).get("agents", []), "pi", errors)
    return {"errors": errors, "warnings": warnings}


def validate_agents(agents: list[dict[str, Any]], owner: str, errors: list[str]) -> None:
    seen: set[str] = set()
    for agent in agents:
        agent_id = str(agent.get("id") or "").strip()
        if not agent_id:
            errors.append(f"{owner} agent name cannot be empty")
            continue
        safe = slugify_agent_id(agent_id)
        if safe != agent_id:
            errors.append(f"{owner} agent '{agent_id}' must use lowercase letters, numbers, and hyphens")
        if agent_id in seen:
            errors.append(f"{owner} has duplicate agent '{agent_id}'")
        seen.add(agent_id)


def slugify_agent_id(value: str) -> str:
    slug = re.sub(r"[^a-z0-9-]+", "-", value.strip().lower())
    slug = re.sub(r"-+", "-", slug).strip("-")
    return slug or "new-agent"


def agent_path(agent: dict[str, Any], base: Path) -> Path:
    existing = str(agent.get("file") or "")
    if existing:
        return Path(existing)
    return base / f"{slugify_agent_id(str(agent.get('id') or 'new-agent'))}.md"


def merge_llama_models(llama_data: Any, edited: list[dict[str, Any]]) -> Any:
    models = llama_data.setdefault("models", {})
    for item in edited:
        model_id = item["id"]
        current = models.setdefault(model_id, {})
        current["name"] = item.get("name") or model_id
        current["description"] = item.get("description") or ""
        ttl = item.get("ttl")
        if ttl not in ("", None):
            current["ttl"] = int(ttl)
        current["cmd"] = item.get("cmd") or ""
    return llama_data


def save_state(payload: dict[str, Any]) -> dict[str, Any]:
    validation = validate_state(payload)
    if validation["errors"]:
        return {"ok": False, "validation": validation}

    yaml, llama_data = load_llama_yaml()
    backups = []
    for path in [LLAMA_CONFIG, OPENCODE_CONFIG, PI_MODELS, PI_SETTINGS]:
        made = backup(path)
        if made:
            backups.append(made)
    for agent in payload.get("opencode", {}).get("agentFiles", []):
        made = backup(agent_path(agent, OPENCODE_AGENTS))
        if made:
            backups.append(made)
    for agent in payload.get("pi", {}).get("agents", []):
        made = backup(agent_path(agent, PI_AGENTS))
        if made:
            backups.append(made)

    llama_data = merge_llama_models(llama_data, payload.get("llama", {}).get("models", []))
    dump_llama_yaml(yaml, llama_data)

    models = normalized_models(llama_data)
    save_opencode(payload, models)
    save_pi(payload, models)
    return {"ok": True, "backups": backups, "validation": validate_state(load_state())}


def save_opencode(payload: dict[str, Any], models: list[dict[str, Any]]) -> None:
    opencode = read_json(OPENCODE_CONFIG, {})
    edited = payload.get("opencode", {})
    opencode["model"] = edited.get("model", opencode.get("model", ""))
    opencode["small_model"] = edited.get("small_model", opencode.get("small_model", ""))
    opencode["default_agent"] = edited.get("default_agent", opencode.get("default_agent", ""))
    provider = opencode.setdefault("provider", {}).setdefault("llamaswap", {})
    provider["models"] = provider_model_entries(models, include_aliases=True)

    agent_map = opencode.setdefault("agent", {})
    for agent in edited.get("agentFiles", []):
        fm = dict(agent.get("frontmatter") or {})
        fm["name"] = agent.get("id") or fm.get("name")
        if agent.get("description") is not None:
            fm["description"] = agent.get("description")
        if agent.get("model") is not None:
            fm["model"] = agent.get("model")
        if agent.get("mode") is not None and agent.get("mode") != "":
            fm["mode"] = agent.get("mode")
        agent["frontmatter"] = fm
        path = agent_path(agent, OPENCODE_AGENTS)
        agent["file"] = str(path)
        write_text_atomic(path, dump_frontmatter(agent))
        agent_map[fm["name"]] = {k: v for k, v in fm.items() if k not in {"name", "description"}}
    write_json_atomic(OPENCODE_CONFIG, opencode)


def save_pi(payload: dict[str, Any], models: list[dict[str, Any]]) -> None:
    pi_models = read_json(PI_MODELS, {})
    provider = pi_models.setdefault("providers", {}).setdefault("llamaswap", {})
    provider["models"] = pi_model_list(models)
    write_json_atomic(PI_MODELS, pi_models)

    settings = read_json(PI_SETTINGS, {})
    edited = payload.get("pi", {})
    for key in ["defaultProvider", "defaultModel", "defaultThinkingLevel", "enabledModels"]:
        if key in edited:
            settings[key] = edited[key]
    write_json_atomic(PI_SETTINGS, settings)

    for agent in edited.get("agents", []):
        fm = dict(agent.get("frontmatter") or {})
        fm["name"] = agent.get("id") or fm.get("name")
        if agent.get("description") is not None:
            fm["description"] = agent.get("description")
        if agent.get("model") is not None:
            fm["model"] = agent.get("model")
        agent["frontmatter"] = fm
        path = agent_path(agent, PI_AGENTS)
        agent["file"] = str(path)
        write_text_atomic(path, dump_frontmatter(agent))


def runtime_status() -> dict[str, Any]:
    return {
        "gpu": run_capture(["nvidia-smi", "--query-gpu=name,memory.used,memory.free,utilization.gpu", "--format=csv,noheader"]),
        "running": running_models(),
        "backend": http_ok("http://127.0.0.1:5100/running"),
        "router": http_ok("http://127.0.0.1:5099/running"),
    }


def run_capture(args: list[str]) -> dict[str, Any]:
    try:
        proc = subprocess.run(args, text=True, capture_output=True, timeout=3, check=False)
        return {"ok": proc.returncode == 0, "text": (proc.stdout or proc.stderr).strip()}
    except Exception as exc:
        return {"ok": False, "text": str(exc)}


def http_ok(url: str) -> bool:
    proc = subprocess.run(
        ["curl", "-sf", "--max-time", "1", "-H", f"Authorization: Bearer {os.environ.get('LLAMA_API_KEY', 'llama-local')}", url],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return proc.returncode == 0


def running_models() -> list[dict[str, Any]]:
    proc = subprocess.run(
        ["curl", "-sf", "--max-time", "1", "-H", f"Authorization: Bearer {os.environ.get('LLAMA_API_KEY', 'llama-local')}", "http://127.0.0.1:5099/running"],
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        return []
    try:
        data = json.loads(proc.stdout or "{}")
        return data.get("running", []) if isinstance(data.get("running"), list) else []
    except Exception:
        return []


def restart_services() -> dict[str, Any]:
    stop = run_capture([str(HOME / ".local/bin/llm-stop")])
    start = run_capture([str(HOME / ".local/bin/llm-start")])
    return {"ok": bool(start["ok"]), "stop": stop, "start": start, "runtime": runtime_status()}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "command",
        choices=[
            "load",
            "status",
            "save",
            "restart",
            "validate",
            "local-models",
            "cookbook",
            "cookbook-search",
            "hf-search",
            "hf-files",
            "add-local",
            "hf-download",
            "set-favorite",
            "set-tried",
            "set-note",
            "set-rating",
            "add-custom",
            "remove-custom",
        ],
    )
    parser.add_argument("payload", nargs="?")
    args = parser.parse_args()
    try:
        if args.command == "load":
            result = load_state()
        elif args.command == "status":
            result = runtime_status()
        elif args.command == "validate":
            result = validate_state(load_state())
        elif args.command == "save":
            if not args.payload:
                raise RuntimeError("save requires JSON payload")
            result = save_state(json.loads(args.payload))
        elif args.command == "restart":
            result = restart_services()
        elif args.command == "local-models":
            result = {"ok": True, "models": discover_local_models()}
        elif args.command == "cookbook":
            result = load_cookbook()
        elif args.command == "cookbook-search":
            payload = json.loads(args.payload or "{}")
            result = {
                "ok": True,
                "recipes": search_recipes(
                    str(payload.get("query") or ""),
                    source_filter=str(payload.get("source", "all")),
                ),
            }
        elif args.command == "hf-search":
            payload = json.loads(args.payload or "{}")
            result = {"ok": True, "models": hf_search(str(payload.get("query") or "GGUF"))}
        elif args.command == "hf-files":
            payload = json.loads(args.payload or "{}")
            result = {"ok": True, "files": hf_model_files(str(payload.get("repo") or ""))}
        elif args.command == "add-local":
            payload = json.loads(args.payload or "{}")
            result = add_model_to_router(
                str(payload.get("path") or ""),
                model_id=str(payload.get("id") or ""),
                name=str(payload.get("name") or ""),
                description=str(payload.get("description") or ""),
                context=int(payload.get("context") or 65536),
            )
        elif args.command == "set-favorite":
            payload = json.loads(args.payload or "{}")
            result = set_recipe_favorite(
                str(payload.get("repo") or ""),
                str(payload.get("favorite", "false")).lower() == "true",
            )
        elif args.command == "set-tried":
            payload = json.loads(args.payload or "{}")
            result = set_recipe_tried(
                str(payload.get("repo") or ""),
                str(payload.get("tried", "false")).lower() == "true",
            )
        elif args.command == "set-note":
            payload = json.loads(args.payload or "{}")
            result = set_recipe_note(
                str(payload.get("repo") or ""),
                str(payload.get("note") or ""),
            )
        elif args.command == "set-rating":
            payload = json.loads(args.payload or "{}")
            result = set_recipe_rating(
                str(payload.get("repo") or ""),
                int(payload.get("rating", 0)),
            )
        elif args.command == "add-custom":
            payload = json.loads(args.payload or "{}")
            result = add_custom_recipe(payload)
        elif args.command == "remove-custom":
            payload = json.loads(args.payload or "{}")
            result = remove_custom_recipe(str(payload.get("repo") or ""))
        else:
            payload = json.loads(args.payload or "{}")
            result = download_hf_model(
                str(payload.get("repo") or ""),
                str(payload.get("file") or ""),
                model_id=str(payload.get("id") or ""),
                name=str(payload.get("name") or ""),
                context=int(payload.get("context") or 65536),
            )
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
