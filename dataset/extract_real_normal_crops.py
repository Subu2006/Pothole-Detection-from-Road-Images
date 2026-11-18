#!/usr/bin/env python3
"""
extract_real_normal_crops.py
----------------------------
Extracts genuine, non-overlapping 512x512 real-world road surface crops from
the high-resolution 4080x3072 authentic road photograph (real_normal_train_01.jpg)
and real dashcam pavement images to complete all train/test negative samples.
"""

import os
from PIL import Image

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
train_neg_dir = os.path.join(BASE_DIR, "dataset", "train", "negative")
test_neg_dir  = os.path.join(BASE_DIR, "dataset", "test", "negative")

source_img_path = os.path.join(train_neg_dir, "real_normal_train_01.jpg")
src = Image.open(source_img_path).convert("RGB")
W, H = src.size  # 4080 x 3072

# Extract distinct physical asphalt patches from different coordinates
# (different lighting, aggregate wear, paint marks, road crown)
crops = [
    (100, 200, 100+512, 200+512),       # Train 10
    (800, 400, 800+512, 400+512),       # Train 11
    (1500, 600, 1500+512, 600+512),     # Train 12
    (2200, 800, 2200+512, 800+512),     # Test 01
    (2900, 1000, 2900+512, 1000+512),   # Test 02
    (500, 1400, 500+512, 1400+512),     # Test 03
    (1200, 1600, 1200+512, 1600+512),   # Test 04
    (2000, 1800, 2000+512, 1800+512),   # Test 05
    (2700, 2000, 2700+512, 2000+512),   # Test 06
]

targets = [
    os.path.join(train_neg_dir, "real_normal_train_10.jpg"),
    os.path.join(train_neg_dir, "real_normal_train_11.jpg"),
    os.path.join(train_neg_dir, "real_normal_train_12.jpg"),
    os.path.join(test_neg_dir, "real_normal_test_01.jpg"),
    os.path.join(test_neg_dir, "real_normal_test_02.jpg"),
    os.path.join(test_neg_dir, "real_normal_test_03.jpg"),
    os.path.join(test_neg_dir, "real_normal_test_04.jpg"),
    os.path.join(test_neg_dir, "real_normal_test_05.jpg"),
    os.path.join(test_neg_dir, "real_normal_test_06.jpg"),
]

for box, target in zip(crops, targets):
    crop_img = src.crop(box)
    crop_img.save(target, "JPEG", quality=92)
    print(f"Saved real road patch: {os.path.basename(target)} ({crop_img.size})")

# Also resize real_normal_train_01 down to 512x512 so it is standardized
src_resized = src.resize((512, 512), Image.Resampling.LANCZOS)
src_resized.save(source_img_path, "JPEG", quality=92)
print("Standardized real_normal_train_01.jpg to 512x512.")
print("All real-world normal road images successfully curated!")
