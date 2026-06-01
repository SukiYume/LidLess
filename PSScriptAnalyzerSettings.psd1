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
    #  - PSUseSingularNouns: internal helpers use plural nouns where the object
    #    is naturally a collection (Events, Processes, Keys).
    #  - PSProvideCommentHelp: this is an internal script/module layout; public
    #    usage is documented in README files.
    #  - PSAvoidUsingPositionalParameters: the tiny test runner keeps assertion
    #    calls compact and readable.
    ExcludeRules = @(
        'PSUseApprovedVerbs',
        'PSAvoidUsingWriteHost',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseBOMForUnicodeEncodedFile',
        'PSUseSingularNouns',
        'PSProvideCommentHelp',
        'PSAvoidUsingPositionalParameters'
    )
}
