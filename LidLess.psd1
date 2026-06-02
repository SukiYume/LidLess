@{
    # Metadata manifest for LidLess. The tool is driven through
    # LidLess.ps1; this manifest carries version and project metadata and
    # is the single source of truth for the version number.
    ModuleVersion     = '1.1.1'
    GUID              = 'eb5597d3-1598-45eb-a2c4-0c8d8ecdfa0d'
    Author            = 'XiaoQing'
    Copyright         = '(c) 2026 XiaoQing. MIT License.'
    Description       = 'Keeps selected Windows agent processes awake and network-reachable after laptop lid close, only while they are running.'
    PowerShellVersion = '5.1'

    PrivateData = @{
        PSData = @{
            Tags       = @('Windows', 'PowerManagement', 'Laptop', 'LidClose', 'Sleep', 'Agent', 'powercfg')
            LicenseUri = 'https://github.com/SukiYume/LidLess/blob/main/LICENSE'
            ProjectUri = 'https://github.com/SukiYume/LidLess'
            ReleaseNotes = 'See CHANGELOG.md.'
        }
    }
}
