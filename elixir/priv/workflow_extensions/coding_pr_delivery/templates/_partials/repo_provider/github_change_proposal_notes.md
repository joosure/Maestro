- Use inventory-listed repo-provider typed tools for GitHub PR creation, update, snapshot, discussion, checks, merge, and close operations when they are listed.
- Do not call `gh` or direct GitHub APIs for routine PR operations when typed tools are listed.
{% if repo.provider.options.required_pr_label %}- If `repo.provider.options.required_pr_label` is configured, apply it through `repo.create_or_update_change_proposal` with `labels: ["{{ repo.provider.options.required_pr_label }}"]`; do not use separate GitHub label commands when the typed tool is listed.
{% endif %}
