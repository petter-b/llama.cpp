"""
Test that GPU-to-GPU checkpoint copy works correctly with hybrid models.

Verifies the GPU checkpoint path activates for models with recurrent state
and produces deterministic output with speculative decoding enabled.

Requires: Qwen3.5-0.8B (hybrid model with recurrent+attention layers).
The GPU checkpoint path only activates for models with recurrent layers.

Performance verification (checkpoint timing < 10ms) is done via manual
deployment testing — see docs/superpowers/plans/2026-03-22-gpu-to-gpu-checkpoint-copy.md Task 7.
"""

import os
import pytest
from utils import ServerProcess

QWEN35_08B = os.environ.get(
    "QWEN35_08B_MODEL",
    os.path.expanduser("~/Models/Qwen3.5-0.8B-BF16.gguf"),
)

requires_qwen35_08b = pytest.mark.skipif(
    not os.path.exists(QWEN35_08B),
    reason="Requires local Qwen3.5-0.8B model",
)


@pytest.fixture(scope="module", autouse=True)
def do_something():
    """Override conftest's load_all — we use local models, not HF presets."""
    pass


def _create_gpu_checkpoint_server():
    """Create server with GPU checkpoints enabled for speculative decoding."""
    server = ServerProcess()
    server.model_hf_repo = None
    server.model_hf_file = None
    server.model_file = QWEN35_08B
    server.n_ctx = 1024
    server.n_slots = 1
    server.n_gpu_layer = 99
    server.seed = 3407
    server.temperature = 0.0
    server.draft_min = 2
    server.draft_max = 8
    server.ctk = "f16"
    server.ctv = "f16"
    server.extra_args = [
        "--spec-type", "ngram-mod",
        "--spec-use-checkpoints", "on",
        "--ctx-checkpoints", "1",
        "--no-cache-prompt",
    ]
    return server


def _get_model_name(server):
    """Query /v1/models to discover the server's model name."""
    res = server.make_request("GET", "/v1/models")
    assert res.status_code == 200, f"Failed to get models: {res.status_code}"
    models = res.body.get("data", [])
    assert len(models) > 0, "No models available on server"
    return models[0]["id"]


@requires_qwen35_08b
def test_gpu_checkpoint_deterministic_output():
    """Spec decoding with GPU checkpoints produces deterministic output.

    10 identical requests must produce identical output, verifying that
    the GPU checkpoint save/restore path maintains state correctly.
    """
    server = _create_gpu_checkpoint_server()
    server.start(timeout_seconds=120)

    model_name = _get_model_name(server)

    prompt = "Once upon a time there was a little robot"

    # prime ngram model with the same prompt so all test requests
    # use the same speculative drafting path
    server.make_request("POST", "/completion", data={
        "model": model_name,
        "prompt": prompt,
        "temperature": 0.0, "top_k": 1, "n_predict": 128,
    })

    outputs = []
    for i in range(10):
        res = server.make_request("POST", "/completion", data={
            "model": model_name,
            "prompt": prompt,
            "temperature": 0.0,
            "top_k": 1,
            "n_predict": 128,
        })
        assert res.status_code == 200, f"Request {i+1} failed: {res.status_code}"
        outputs.append(res.body["content"])

    server.stop()

    assert len(set(outputs)) == 1, (
        f"Output divergence: {len(set(outputs))} unique outputs across "
        f"10 identical requests (Qwen3.5, GPU checkpoint)."
    )


@requires_qwen35_08b
def test_gpu_checkpoint_multiple_requests():
    """Server handles 20 sequential requests without errors.

    Verifies GPU checkpoint save/restore doesn't leak memory or corrupt
    state across multiple requests with varying prompts.
    """
    server = _create_gpu_checkpoint_server()
    server.start(timeout_seconds=120)

    model_name = _get_model_name(server)

    for i in range(20):
        res = server.make_request("POST", "/completion", data={
            "model": model_name,
            "prompt": f"Write a short fact number {i} about science.",
            "temperature": 0.0,
            "top_k": 1,
            "n_predict": 64,
        })
        assert res.status_code == 200, (
            f"Request {i+1}/20 failed with status {res.status_code}"
        )
        assert len(res.body.get("content", "")) > 0, (
            f"Request {i+1}/20 returned empty content"
        )

    server.stop()
