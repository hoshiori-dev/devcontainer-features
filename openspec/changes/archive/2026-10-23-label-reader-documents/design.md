# Design

## Context

The root-file fallback in areaOf currently classifies the four documents as harness files.

## Goals / Non-Goals

Use an exact list of the four root paths before the fallback; verify with mapping and mixed-area tests. Preserve the
existing label update policy.

## Decisions

Add document to AREAS and declare area:document. Match the four filenames explicitly instead of all Markdown files, so
agent guidance keeps its harness classification. Keep the area's name consistent in workflow guidance and templates.

## Risks / Trade-offs

Existing area:harness labels remain on older PRs because area labels are additive.
