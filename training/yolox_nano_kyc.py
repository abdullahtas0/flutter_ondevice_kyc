"""YOLOX-Nano experiment for the three KYC classes.

Copy this file onto the PYTHONPATH of an Apache-2.0 YOLOX checkout, or run
tools/train.py with -f pointing here after `pip install -e .` inside YOLOX.
Input size is 416. Depth and width match the nano variant.
"""

from yolox.exp import Exp as MyExp


class Exp(MyExp):
    def __init__(self):
        super().__init__()
        self.num_classes = 3
        self.depth = 0.33
        self.width = 0.25
        self.input_size = (416, 416)
        self.test_size = (416, 416)
        self.exp_name = "yolox_nano_kyc"
        self.max_epoch = 50
        self.data_dir = "training/out/synthetic"
        self.train_ann = "instances_train.json"
        self.val_ann = "instances_val.json"
