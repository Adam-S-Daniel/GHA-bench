# conftest.py — make the project root importable from the tests/ package so
# `import version_bumper` resolves no matter where pytest is invoked from.
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
