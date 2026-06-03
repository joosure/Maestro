{% if runtime.retry.attempt %}
Continuation context:

- This is retry attempt #{{ runtime.retry.attempt }} because the issue is still in an active state.
- Resume from the current workspace state instead of restarting from scratch.
- Do not repeat already-completed investigation or validation unless needed for new code changes.
- Do not end the turn while the issue remains in an active state unless you are blocked by missing required typed tools, permissions, or secrets.
{% endif %}
