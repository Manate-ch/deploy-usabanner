# UsaBanner module manifest. PowerShellVersion is 5.1 on purpose: Windows
# PowerShell must be able to import the module, so that each command can
# hand itself to pwsh (UsaBanner.psm1 says how).
@{
    RootModule           = 'UsaBanner.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '27da0669-2d84-41c1-aa5e-217086ee70cc'
    Author               = 'Tyson C Rasanen'
    CompanyName          = 'UsagiTools'
    Copyright            = 'Copyright (c) 2026 Tyson C Rasanen. MIT licence.'
    Description          = 'Login banners for Windows Server and Ubuntu: at the console before login, before SSH authentication, and after login.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @('New-UsaBannerArt', 'Show-UsaBanner', 'Show-UsaBannerArt')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
}
