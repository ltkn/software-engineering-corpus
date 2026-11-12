"""Tiny Qwen4-Exp source checkpoint + char-level tokenizer with a ChatML template."""
import json, sys
from dataclasses import asdict
from pathlib import Path
sys.path.insert(0, __import__("os").environ["OMLX_REPO"])
import mlx.core as mx
from mlx.utils import tree_flatten
from tests.test_mlx_vlm_qwen4_exp_compat import _tiny_config
from mlx_vlm.models.qwen4_exp.language import configure_mtp_runtime, configure_ple_runtime
from mlx_vlm.models.qwen4_exp.qwen4_exp import Model
from tokenizers import Tokenizer, Regex, models, normalizers, pre_tokenizers
from transformers import PreTrainedTokenizerFast

source = Path(sys.argv[1]); source.mkdir(parents=True, exist_ok=True)
cfg = _tiny_config(); cfg.text_config.linear_key_head_dim = 32; cfg.text_config.linear_value_head_dim = 32
index = source / "model.safetensors.index.json"
index.write_text(json.dumps({"weight_map": {"mtp.fc_hidden.weight": "model.safetensors"}}))
configure_ple_runtime(source, mode="resident"); configure_mtp_runtime(source, enabled=True)
mx.random.seed(7); model = Model(cfg); model.eval()
w = {k: v.astype(mx.bfloat16) if v.dtype == mx.float32 else v for k, v in tree_flatten(model.parameters())}
sk = next(k for k in w if k.endswith("ngram_embedding.weight_scale")); w[sk] = mx.array([0.25], dtype=mx.bfloat16)
config = asdict(cfg); config["architectures"] = ["Qwen4ExpForConditionalGeneration"]
config["text_config"]["mtp_num_hidden_layers"] = 1
(source / "config.json").write_text(json.dumps(config))
mx.save_safetensors(str(source / "model.safetensors"), w)
index.write_text(json.dumps({"weight_map": {k: "model.safetensors" for k in w}}))

specials = ["<|endoftext|>", "<|im_start|>", "<|im_end|>", "<think>", "</think>", "[UNK]"]
chars = list("abcdefghijklmnopqrstuvwxyz0123456789 .,:;?!'-_/()\n")
vocab = {t: i for i, t in enumerate(specials + chars)}
assert len(vocab) <= 64, len(vocab)
tk = Tokenizer(models.WordLevel(vocab=vocab, unk_token="[UNK]"))
tk.normalizer = normalizers.Lowercase()
tk.pre_tokenizer = pre_tokenizers.Split(Regex(r"[\s\S]"), behavior="isolated")
tk.add_special_tokens(specials[:5])
template = (
    "{% for m in messages %}<|im_start|>{{ m.role }}\n"
    "{% if m.role == 'assistant' and m.reasoning_content and preserve_thinking %}<think>\n{{ m.reasoning_content }}\n</think>\n\n{% endif %}"
    "{{ m.content }}"
    # Qwen-style tool calls: arguments must be a mapping (OpenAI sends a JSON string).
    "{% for tc in m.tool_calls or [] %}\n<tool_call>\n<function={{ tc.function.name }}>\n"
    "{% for k, v in tc.function.arguments|items %}<parameter={{ k }}>\n{{ v }}\n</parameter>\n{% endfor %}"
    "</function>\n</tool_call>{% endfor %}<|im_end|>\n{% endfor %}"
    "{% if add_generation_prompt %}<|im_start|>assistant\n{% endif %}")
fast = PreTrainedTokenizerFast(tokenizer_object=tk, eos_token="<|im_end|>", unk_token="[UNK]",
                               pad_token="<|endoftext|>", chat_template=template)
fast.save_pretrained(str(source))
print("tiny source ->", source, "vocab", len(vocab))
