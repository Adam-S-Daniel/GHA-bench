"""Make the top-level script importable from tests/ regardless of CWD."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
