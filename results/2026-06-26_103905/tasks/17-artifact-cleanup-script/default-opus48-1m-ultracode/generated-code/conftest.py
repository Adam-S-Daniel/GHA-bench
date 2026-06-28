"""
pytest configuration.

The presence of this file at the project root makes pytest insert this
directory at the front of ``sys.path`` (default "prepend" import mode), so the
test modules under ``tests/`` can ``import artifact_cleanup`` directly without
any packaging or installation step.
"""
