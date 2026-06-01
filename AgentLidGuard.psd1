@{
    # Metadata manifest for AgentLidGuard. The tool is driven through
    # AgentLidGuard.ps1; this manifest carries version and project metadata and
    # is the single source of truth for the version number.
    ModuleVersion     = '1.0.0'
    GUID              = 'eb5597d3-1598-45eb-a2c4-0c8d8ecdfa0d'
    Author            = 'Echo'
    Copyright         = '(c) 2026 Echo. MIT License.'
    Description       = 'Keeps selected Windows agent processes awake and network-reachable after laptop lid close, only while they are running.'
    PowerShellVersion = '5.1'

    PrivateData = @{
        PSData = @{
            Tags       = @('Windows', 'PowerManagement', 'Laptop', 'LidClose', 'Sleep', 'Agent', 'powercfg')
            LicenseUri = 'https://github.com/OWNER/AgentLidGuard/blob/main/LICENSE'
            ProjectUri = 'https://github.com/OWNER/AgentLidGuard'
            ReleaseNotes = 'See CHANGELOG.md.'
        }
    }
}
