## ADDED Requirements

### Requirement: Companion Python editor extensions

The feature SHALL request Microsoft's `ms-python.python` and `ms-python.vscode-python-envs` extensions through VS Code
customizations. It SHALL declare no editor settings or IDE backend and SHALL preserve its CLI installation, tool, and
environment behavior independently of editor choice.

#### Scenario: Python extension declarations

- **WHEN** a supporting editor reads the feature's VS Code customizations
- **THEN** its extension list requests `ms-python.python` and `ms-python.vscode-python-envs`
- **AND** no project interpreter, formatter, or IDE backend is selected by the feature

### Requirement: Python editor integration guidance

`NOTES.md` SHALL explain the supplied extensions, project environment discovery, optional Jupyter support, native
PyCharm uv integration, and the VS Code mechanism for excluding the supplied automatic-install requests. It SHALL
explain that consumers also receive these defaults when uv is installed as another feature's dependency.

#### Scenario: CLI-only extension exclusion

- **WHEN** a developer uses uv only for command-line tools or receives it through a dependent feature
- **THEN** the notes show `-ms-python.python` and `-ms-python.vscode-python-envs` in project customizations
- **AND** explain that exclusion does not uninstall existing extensions or remove requests from other sources
- **AND** Jupyter and project kernel setup are documented as additional notebook-specific choices
