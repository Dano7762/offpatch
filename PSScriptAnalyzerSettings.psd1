@{
    # Analyse statique d'OffPatch : erreurs et avertissements bloquants.
    Severity     = @('Error', 'Warning')
    # Les scripts de tests/runner écrivent leur sortie pour le journal du runner.
    ExcludeRules = @('PSAvoidUsingWriteHost')
    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1')
        }
    }
}
