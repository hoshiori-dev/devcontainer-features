## ADDED Requirements

### Requirement: Companion editor extension

The feature SHALL request `denoland.vscode-deno` through VS Code customizations and the official JetBrains `deno` plugin
through JetBrains customizations. It SHALL declare no editor settings or IDE backend and SHALL leave CLI installation
behavior independent of editor choice.

#### Scenario: Companion extension declaration

- **WHEN** a supporting editor reads the feature's VS Code customizations
- **THEN** the extension list requests `denoland.vscode-deno`
- **AND** the feature declares no editor settings or IDE backend

#### Scenario: JetBrains companion declaration

- **WHEN** a supporting JetBrains client reads the feature customizations
- **THEN** its plugin list requests `deno` without selecting an IDE backend

### Requirement: Project-controlled editor activation

`NOTES.md` SHALL explain project-controlled Deno activation, including partial activation in mixed Node/Deno workspaces,
and use of the supplied official JetBrains Deno plugin. It SHALL distinguish project examples from configuration
supplied by the feature.

#### Scenario: Project-controlled activation

- **WHEN** a developer reads the editor guidance
- **THEN** it offers `deno.enable` for a Deno project and `deno.enablePaths` for selected mixed-project directories
- **AND** it identifies the supplied JetBrains plugin and leaves compatible IDE backend selection to the project
- **AND** it does not claim that installing the feature enables Deno language services throughout the workspace

### Requirement: Documented extension exclusion

`NOTES.md` SHALL document the VS Code mechanism for excluding the feature's default extension using
`-denoland.vscode-deno` in the consuming project's customization. The guidance SHALL describe exclusion from automatic
installation rather than claiming to uninstall an already installed extension.

#### Scenario: Documented extension exclusion

- **WHEN** a developer wants the CLI without its VS Code companion extension
- **THEN** the notes provide a project configuration example using `-denoland.vscode-deno`
- **AND** they explain that exclusion does not uninstall an existing extension
