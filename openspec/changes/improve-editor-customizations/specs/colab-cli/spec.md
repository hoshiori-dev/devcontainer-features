## ADDED Requirements

### Requirement: Companion Colab editor extension

The feature SHALL request Google's `google.colab` extension through VS Code customizations. It SHALL declare no editor
settings or IDE backend and SHALL preserve CLI installation and authentication behavior independently of editor choice.

#### Scenario: Colab extension declaration

- **WHEN** a supporting editor reads the feature's VS Code customizations
- **THEN** its extension list requests `google.colab`
- **AND** no Google account, Colab session, runtime, or notebook kernel is selected by the feature

### Requirement: Colab editor integration guidance

`NOTES.md` SHALL identify the supplied official extension and its upstream Jupyter extension dependency, link official
sign-in and kernel-selection guidance, and explain VS Code automatic-install exclusion. It SHALL distinguish the
extension's sessions and sign-in from CLI sessions and authentication without promising shared state or universal client
support.

#### Scenario: Colab extension guidance

- **WHEN** a developer reads the editor integration notes
- **THEN** they identify `google.colab` as supplied and `ms-toolsai.jupyter` as its upstream extension dependency
- **AND** can follow official sign-in and kernel-selection instructions without manually adding the supplied extension
- **AND** see `-google.colab` as automatic-install exclusion, not uninstallation or removal of independently requested
  dependencies
