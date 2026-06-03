"""Shared helpers for quickstart workflow generation scripts."""

from __future__ import annotations

from pathlib import Path

PARTIAL_INCLUDE_PREFIX = "<!-- symphony-include:"
MAX_PARTIAL_INCLUDE_DEPTH = 8


class WorkflowTemplateError(RuntimeError):
    pass


def set_change_proposal_gate(
    workflow_text: str, gate_name: str, enabled: bool
) -> str:
    """Set one workflow.reconciliation.change_proposal.gates boolean value."""
    section_marker = "  reconciliation:\n    change_proposal:\n"
    gates_marker = "      gates:\n"
    start = workflow_text.find(section_marker)
    if start == -1:
        raise WorkflowTemplateError(
            "workflow template does not contain workflow.reconciliation.change_proposal"
        )
    gates_start = workflow_text.find(gates_marker, start)
    if gates_start == -1:
        raise WorkflowTemplateError(
            "workflow template does not contain change_proposal.gates"
        )

    next_top_level = workflow_text.find("\ntracker:\n", gates_start)
    search_end = next_top_level if next_top_level != -1 else len(workflow_text)
    prefix = f"        {gate_name}: "
    lines = workflow_text[gates_start:search_end].splitlines(keepends=True)

    updated_lines: list[str] = []
    replaced = False
    for line in lines:
        if line.startswith(prefix):
            suffix = "\n" if line.endswith("\n") else ""
            updated_lines.append(f"{prefix}{str(enabled).lower()}{suffix}")
            replaced = True
        else:
            updated_lines.append(line)

    if not replaced:
        raise WorkflowTemplateError(
            f"workflow template does not contain change_proposal.gates.{gate_name}"
        )

    return (
        workflow_text[:gates_start]
        + "".join(updated_lines)
        + workflow_text[search_end:]
    )


def expand_workflow_partials(
    workflow_text: str, source_path: Path, repo_root: Path, depth: int = 0
) -> str:
    if depth > MAX_PARTIAL_INCLUDE_DEPTH:
        raise WorkflowTemplateError(
            "workflow partial include nesting is too deep "
            f"(max {MAX_PARTIAL_INCLUDE_DEPTH})"
        )

    expanded_lines: list[str] = []
    for line in workflow_text.splitlines():
        partial_ref = parse_partial_include(line)
        if partial_ref is None:
            expanded_lines.append(line)
            continue

        partial_path = resolve_partial(repo_root, source_path, partial_ref)
        partial_text = partial_path.read_text(encoding="utf-8")
        expanded_lines.append(
            expand_workflow_partials(partial_text, partial_path, repo_root, depth + 1)
        )

    suffix = "\n" if workflow_text.endswith("\n") else ""
    return "\n".join(expanded_lines) + suffix


def parse_partial_include(line: str) -> str | None:
    stripped = line.strip()
    if not stripped.startswith(PARTIAL_INCLUDE_PREFIX) or not stripped.endswith("-->"):
        return None

    partial_ref = stripped[len(PARTIAL_INCLUDE_PREFIX) : -len("-->")].strip()
    if not partial_ref:
        raise WorkflowTemplateError("workflow partial include is blank")
    return partial_ref


def resolve_partial(repo_root: Path, source_path: Path, partial_ref: str) -> Path:
    partial = partial_ref.strip().replace("\\", "/")
    if Path(partial).is_absolute() or ".." in Path(partial).parts:
        raise WorkflowTemplateError(f"invalid workflow partial include: {partial_ref}")
    if not partial.endswith(".md"):
        raise WorkflowTemplateError(
            f"workflow partial include must point to a .md file: {partial_ref}"
        )

    if partial.startswith("_partials/"):
        partial_path = (
            repo_root / "elixir" / "priv" / "workflow_templates" / partial
        ).resolve()
    else:
        partial_path = (source_path.parent / partial).resolve()

    partials_root = (
        repo_root / "elixir" / "priv" / "workflow_templates" / "_partials"
    ).resolve()
    try:
        partial_path.relative_to(partials_root)
    except ValueError as error:
        raise WorkflowTemplateError(
            f"workflow partial include must stay under _partials: {partial_ref}"
        ) from error

    if not partial_path.is_file():
        raise WorkflowTemplateError(f"workflow partial not found: {partial_path}")
    return partial_path
