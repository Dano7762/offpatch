@{
    RootModule           = 'OffPatch.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '5cb849d6-934f-4dcf-a221-b1ad671fbef1'
    Author               = 'David Informaticien'
    Copyright            = '(c) 2026 David Informaticien. Licence MIT.'
    Description          = 'OffPatch : dépôt mensuel de mises à jour Microsoft et installation hors ligne, poste par poste.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop')
    # Liste explicite : une entrée par fichier de Public/ (contrôlé par tests/Unit/Module.Tests.ps1).
    FunctionsToExport    = @('Initialize-OpSession')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            LicenseUri = 'https://github.com/Dano7762/offpatch/blob/master/LICENSE'
            ProjectUri = 'https://github.com/Dano7762/offpatch'
        }
    }
}
