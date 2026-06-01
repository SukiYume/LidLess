@{
    # Run all default rules; CI only fails on Error-severity findings.
    IncludeDefaultRules = $true

    # Rules intentionally excluded for this project:
    #  - PSUseApprovedVerbs: a few internal helpers use descriptive verbs
    #    (Ensure-/Normalize-) that read more clearly than approved equivalents.
    #  - PSAvoidUsingWriteHost: the CLI deliberately writes human-readable
    #    status to the host.
    #  - PSUseShouldProcessForStateChangingFunctions: this is a CLI tool, not a
    #    reusable cmdlet library; ShouldProcess plumbing would add noise.
    #  - PSUseBOMForUnicodeEncodedFile: files are UTF-8 without BOM by design.
    ExcludeRules = @(
        'PSUseApprovedVerbs',
        'PSAvoidUsingWriteHost',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseBOMForUnicodeEncodedFile'
    )
}
