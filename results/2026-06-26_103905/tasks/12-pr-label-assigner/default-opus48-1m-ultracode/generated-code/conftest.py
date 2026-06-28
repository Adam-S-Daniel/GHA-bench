# Empty root conftest.py.
# Its presence makes the project root the pytest rootdir and (under the default
# "prepend" import mode) puts the root on sys.path, so tests can simply
# `import pr_label_assigner` without packaging boilerplate.
