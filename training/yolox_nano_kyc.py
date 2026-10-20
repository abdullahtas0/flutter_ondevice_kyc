"""YOLOX-Nano experiment for the three KYC classes.

Run tools/train.py with -f pointing here and PYTHONPATH set to an
Apache-2.0 YOLOX checkout. Do not pip install that checkout: its setup
pulls onnx-simplifier. Images live under data_dir/train2017 and
data_dir/val2017. Input size is 416. Depth and width match the nano variant.
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
        self.data_num_workers = 2
        self.data_dir = "training/out/synthetic"
        self.train_ann = "instances_train.json"
        self.val_ann = "instances_val.json"
