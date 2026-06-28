# Presence of a conftest.py at the repo root puts the root on sys.path under
# pytest's default "prepend" import mode, so `import secret_rotation_validator`
# resolves both locally and inside the CI container.
