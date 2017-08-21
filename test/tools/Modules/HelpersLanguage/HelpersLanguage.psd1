#
# Module manifest for module 'HelpersLanguage'
#

@{

RootModule = 'HelpersLanguage.psm1'

ModuleVersion = '1.0'

GUID = 'a575af5e-2bd1-427f-b966-48640788896b'

CompanyName = 'Microsoft Corporation'

Copyright = 'Copyright (C) Microsoft Corporation, All rights reserved.'

Description = 'Temporary module for language tests'

FunctionsToExport = 'Get-ParseResults', 'Get-RuntimeError', 'ShouldBeParseError',
                    'Test-ErrorStmt', 'Test-Ast', 'Test-ErrorStmtForSwitchFlag'

}
