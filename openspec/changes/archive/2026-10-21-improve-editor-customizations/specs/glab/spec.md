## ADDED Requirements

### Requirement: Companion GitLab editor extensions

The feature SHALL request `GitLab.gitlab-workflow` through VS Code customizations and GitLab's `com.gitlab.plugin`
through JetBrains customizations. It SHALL declare no editor settings or IDE backend and SHALL preserve CLI installation
and authentication behavior independently of editor choice.

#### Scenario: GitLab extension declarations

- **WHEN** a supporting editor reads the feature customizations
- **THEN** VS Code customizations request `GitLab.gitlab-workflow` and JetBrains customizations request
  `com.gitlab.plugin`
- **AND** no account, token, instance URL, or IDE backend is configured by the feature

### Requirement: GitLab editor integration guidance

`NOTES.md` SHALL identify the supplied official plugins, link their setup instructions, distinguish editor sign-in from
CLI authentication, and document VS Code automatic-install exclusion. It SHALL explain GitLab's requirement to install
its JetBrains plugin on the remote backend only and SHALL NOT claim a JetBrains exclusion syntax without official
support.

#### Scenario: GitLab extension guidance

- **WHEN** a developer reads the editor integration notes
- **THEN** they identify the plugins supplied by the feature without requiring the user to add them manually
- **AND** show `-GitLab.gitlab-workflow` as VS Code automatic-install exclusion, not uninstallation
- **AND** explain remote-backend installation and user-controlled editor authentication and IDE selection
