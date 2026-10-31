"""Local, explicit implementation of the pinned CIFAR VGG-16-BN architecture.

Architecture/state-dict layout follows chenyaofo/pytorch-cifar-models.
Upstream source and BSD license are retained in reference/upstream/.
No remote code is executed when loading a checkpoint.
"""
from pathlib import Path
import json
import torch
from torch import nn

PROJECT=Path(__file__).resolve().parent
CONFIG=json.loads((PROJECT/'config.json').read_text())
BLOCKS=((64,64),(128,128),(256,256,256),(512,512,512),(512,512,512))

class CifarVGG16BN(nn.Module):
    def __init__(self):
        super().__init__()
        layers=[]
        channels=3
        for block in BLOCKS:
            for out in block:
                layers.extend([nn.Conv2d(channels,out,3,padding=1),nn.BatchNorm2d(out),nn.ReLU(inplace=False)])
                channels=out
            layers.append(nn.MaxPool2d(2,2))
        self.features=nn.Sequential(*layers)
        self.classifier=nn.Sequential(nn.Linear(512,512),nn.ReLU(inplace=False),nn.Dropout(),
                                      nn.Linear(512,512),nn.ReLU(inplace=False),nn.Dropout(),nn.Linear(512,10))

    def forward(self,x):
        return self.classifier(torch.flatten(self.features(x),1))

def load_model():
    model=CifarVGG16BN()
    state=torch.load(PROJECT/CONFIG['checkpoint'],map_location='cpu',weights_only=True)
    model.load_state_dict(state,strict=True)
    return model.eval()

def conv_layers(model):
    return [(name,module) for name,module in model.named_modules() if isinstance(module,nn.Conv2d)]
