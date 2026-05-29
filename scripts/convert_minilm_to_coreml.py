#!/usr/bin/env python3
"""
Converts sentence-transformers/all-MiniLM-L6-v2 directly from PyTorch to CoreML (Float16).
Avoids the ONNX intermediary since coremltools 9+ does not support source="onnx".
Also exports the BERT vocabulary vocab.txt to MeetMind/Resources.
Renames the model output feature name to "embedding" by saving, renaming, and reloading.
"""

import os
import sys
import shutil
import warnings
warnings.filterwarnings("ignore")
os.environ["TOKENIZERS_PARALLELISM"] = "false"

import numpy as np
import torch
import torch.nn as nn
from transformers import AutoModel, AutoTokenizer
import coremltools as ct

# ── Config ────────────────────────────────────────────────────────────────────
MODEL_ID    = "sentence-transformers/all-MiniLM-L6-v2"
MAX_SEQ_LEN = 128
OUTPUT_DIR  = os.path.join(os.path.dirname(__file__), "..", "MeetMind", "Resources")
MLPKG_NAME  = "MiniLMEmbedder.mlpackage"
os.makedirs(OUTPUT_DIR, exist_ok=True)

print(f"Loading transformer model and tokenizer: {MODEL_ID}...")
tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
base_model = AutoModel.from_pretrained(MODEL_ID)

# Save vocab.txt for the Swift tokenizer
vocab_files = tokenizer.save_vocabulary(OUTPUT_DIR)
for f in vocab_files:
    if f and os.path.exists(f):
        print(f"📄 Vocab saved: {os.path.basename(f)}")

# Define PyTorch wrapper that does Mean Pooling and L2 Normalization
class CoreMLEmbeddingWrapper(nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_ids, attention_mask, token_type_ids):
        # 1. Transformer output
        outputs = self.model(
            input_ids=input_ids,
            attention_mask=attention_mask,
            token_type_ids=token_type_ids
        )
        # [batch, seq_len, 384]
        last_hidden_state = outputs.last_hidden_state
        
        # 2. Mean pooling
        # attention_mask: [batch, seq_len] -> [batch, seq_len, 1]
        mask_expanded = attention_mask.unsqueeze(-1).expand(last_hidden_state.size()).float()
        
        # Sum hidden states: [batch, 384]
        sum_embeddings = torch.sum(last_hidden_state * mask_expanded, dim=1)
        
        # Sum attention mask elements: [batch, 1]
        sum_mask = mask_expanded.sum(dim=1)
        sum_mask = torch.clamp(sum_mask, min=1e-9)
        
        pooled = sum_embeddings / sum_mask
        
        # 3. L2 Normalization: [batch, 384]
        norm = torch.nn.functional.normalize(pooled, p=2, dim=1)
        return norm

wrapper = CoreMLEmbeddingWrapper(base_model)
wrapper.eval()

# Prepare dummy input for tracing
dummy_input_ids = torch.ones(1, MAX_SEQ_LEN, dtype=torch.int32)
dummy_attention_mask = torch.ones(1, MAX_SEQ_LEN, dtype=torch.int32)
dummy_token_type_ids = torch.zeros(1, MAX_SEQ_LEN, dtype=torch.int32)

print("✍️ Tracing PyTorch model...")
with torch.no_grad():
    traced_model = torch.jit.trace(
        wrapper, 
        (dummy_input_ids, dummy_attention_mask, dummy_token_type_ids)
    )

print("⚙️ Converting PyTorch model to CoreML (Float16)...")
mlmodel = ct.convert(
    traced_model,
    inputs=[
        ct.TensorType(name="input_ids", shape=(1, MAX_SEQ_LEN), dtype=np.int32),
        ct.TensorType(name="attention_mask", shape=(1, MAX_SEQ_LEN), dtype=np.int32),
        ct.TensorType(name="token_type_ids", shape=(1, MAX_SEQ_LEN), dtype=np.int32),
    ],
    compute_precision=ct.precision.FLOAT16,
    minimum_deployment_target=ct.target.macOS13,
    compute_units=ct.ComputeUnit.ALL,
    convert_to="mlprogram"
)

# 1. Save original model first
out_path = os.path.join(OUTPUT_DIR, MLPKG_NAME)
if os.path.exists(out_path):
    shutil.rmtree(out_path)
print("💾 Saving intermediate CoreML model...")
mlmodel.save(out_path)

# 2. Rename the output feature to "embedding"
spec = mlmodel.get_spec()
original_output_name = spec.description.output[0].name
print(f"   Original CoreML output name: '{original_output_name}'")
ct.utils.rename_feature(spec, original_output_name, "embedding")

# 3. Reload model with updated spec and existing weights directory
print("🔄 Reloading model with renamed output and weights...")
weights_dir = os.path.join(out_path, "Data", "com.apple.CoreML", "weights")
mlmodel = ct.models.MLModel(spec, weights_dir=weights_dir)

# 4. Save final renamed model
print("💾 Saving final renamed CoreML model...")
shutil.rmtree(out_path)
mlmodel.save(out_path)

mlmodel.short_description = "all-MiniLM-L6-v2 · 384-dim sentence embeddings · Float16"
mlmodel.author  = "sentence-transformers → MeetMind CoreML"
mlmodel.version = "1.0.0"

# Print final outputs
spec = mlmodel.get_spec()
output_name = spec.description.output[0].name
print(f"   Final CoreML output name: '{output_name}'")
with open(os.path.join(OUTPUT_DIR, "embedding_output_name.txt"), "w") as f:
    f.write(output_name)

total_mb = sum(
    os.path.getsize(os.path.join(r, f))
    for r, _, files in os.walk(out_path) for f in files
) / 1_048_576
print(f"✅ Saved CoreML model to: {out_path} ({total_mb:.1f} MB)")

# 🧪 Quick sanity check
print("🧪 Running sanity check...")
test_text = "Q3 planning meeting."
encoded = tokenizer(test_text, return_tensors="pt", max_length=MAX_SEQ_LEN, padding="max_length", truncation=True)
input_ids = encoded["input_ids"].int()
attention_mask = encoded["attention_mask"].int()
token_type_ids = encoded.get("token_type_ids", torch.zeros_like(input_ids)).int()

# PyTorch output
with torch.no_grad():
    torch_out = wrapper(input_ids, attention_mask, token_type_ids).numpy()

# CoreML output
pred = mlmodel.predict({
    "input_ids": input_ids.numpy(),
    "attention_mask": attention_mask.numpy(),
    "token_type_ids": token_type_ids.numpy()
})
coreml_out = list(pred.values())[0]

print(f"PyTorch shape: {torch_out.shape}, CoreML shape: {coreml_out.shape}")
print(f"CoreML L2 norm: {np.linalg.norm(coreml_out):.4f}")
diff = np.abs(torch_out - coreml_out).max()
print(f"Max absolute difference between PyTorch and CoreML: {diff:.6e}")
if diff < 1e-2:
    print("✅ Conversion and output renaming verified successfully!")
else:
    print("⚠️ High difference observed between PyTorch and CoreML!")
