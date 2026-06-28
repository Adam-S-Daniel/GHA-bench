"""Ensures the project root (where ``label_assigner.py`` lives) is importable
from the ``tests/`` package regardless of where pytest is launched."""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
