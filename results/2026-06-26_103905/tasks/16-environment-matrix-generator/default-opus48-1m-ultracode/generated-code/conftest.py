# Ensures the project root (where matrix_generator.py lives) is importable from
# the tests/ directory when running `pytest` from the repository root.
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
