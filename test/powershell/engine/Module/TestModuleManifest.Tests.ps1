Describe "Test-ModuleManifest tests" -tags "CI" {

    AfterEach {
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue testdrive:/module
    }

    It "module manifest containing paths with backslashes or forwardslashes are resolved correctly" {

        New-Item -ItemType Directory -Path testdrive:/module
        New-Item -ItemType Directory -Path testdrive:/module/foo
        New-Item -ItemType Directory -Path testdrive:/module/bar
        New-Item -ItemType File -Path testdrive:/module/foo/bar.psm1
        New-Item -ItemType File -Path testdrive:/module/bar/foo.psm1
        $testModulePath = "testdrive:/module/test.psd1"
        $fileList = "foo\bar.psm1","bar/foo.psm1"

        New-ModuleManifest -NestedModules $fileList -RootModule foo\bar.psm1 -RequiredAssemblies $fileList -Path $testModulePath -TypesToProcess $fileList -FormatsToProcess $fileList -ScriptsToProcess $fileList -FileList $fileList -ModuleList $fileList

        Test-Path $testModulePath | Should Be $true

        # use -ErrorAction Stop to cause test to fail if Test-ModuleManifest writes to error stream
        Test-ModuleManifest -Path $testModulePath -ErrorAction Stop | Should BeOfType System.Management.Automation.PSModuleInfo
    }

    It "module manifest containing missing files returns error: <parameter>" -TestCases (
        @{parameter = "RequiredAssemblies"; error = "Modules_InvalidRequiredAssembliesInModuleManifest"},
        @{parameter = "NestedModules"; error = "Modules_InvalidNestedModuleinModuleManifest"},
        @{parameter = "RequiredModules"; error = "Modules_InvalidRequiredModulesinModuleManifest"},
        @{parameter = "FileList"; error = "Modules_InvalidFilePathinModuleManifest"},
        @{parameter = "ModuleList"; error = "Modules_InvalidModuleListinModuleManifest"},
        @{parameter = "TypesToProcess"; error = "Modules_InvalidManifest"},
        @{parameter = "FormatsToProcess"; error = "Modules_InvalidManifest"},
        @{parameter = "RootModule"; error = "Modules_InvalidRootModuleInModuleManifest"},
        @{parameter = "ScriptsToProcess"; error = "Modules_InvalidManifest"}
     ) {

        param ($parameter, $error)

        New-Item -ItemType Directory -Path testdrive:/module
        New-Item -ItemType Directory -Path testdrive:/module/foo
        New-Item -ItemType File -Path testdrive:/module/foo/bar.psm1
        $testModulePath = "testdrive:/module/test.psd1"

        $args = @{$parameter = "doesnotexist.psm1"}
        New-ModuleManifest -Path $testModulePath @args
        [string]$errorId = "$error,Microsoft.PowerShell.Commands.TestModuleManifestCommand"

        { Test-ModuleManifest -Path $testModulePath -ErrorAction Stop } | ShouldBeErrorId $errorId
    }

    It "module manifest containing valid unprocessed rootmodule file type succeeds: <rootModuleValue>" -TestCases (
        @{rootModuleValue = "foo.psm1"},
        @{rootModuleValue = "foo.dll"}
    ) {

        param($rootModuleValue)

        New-Item -ItemType Directory -Path testdrive:/module
        $testModulePath = "testdrive:/module/test.psd1"

        New-Item -ItemType File -Path testdrive:/module/$rootModuleValue
        New-ModuleManifest -Path $testModulePath -RootModule $rootModuleValue
        $moduleManifest = Test-ModuleManifest -Path $testModulePath -ErrorAction Stop
        $moduleManifest | Should BeOfType System.Management.Automation.PSModuleInfo
        $moduleManifest.RootModule | Should Be $rootModuleValue
    }

    It "module manifest containing valid processed empty rootmodule file type fails: <rootModuleValue>" -TestCases (
        @{rootModuleValue = "foo.cdxml"; error = "System.Xml.XmlException"},  # fails when cmdlet tries to read it as XML
        @{rootModuleValue = "foo.xaml"; error = "NotSupported"}   # not supported on PowerShell Core
    ) {

        param($rootModuleValue, $error)

        New-Item -ItemType Directory -Path testdrive:/module
        $testModulePath = "testdrive:/module/test.psd1"

        New-Item -ItemType File -Path testdrive:/module/$rootModuleValue
        New-ModuleManifest -Path $testModulePath -RootModule $rootModuleValue
        { Test-ModuleManifest -Path $testModulePath -ErrorAction Stop } | ShouldBeErrorId "$error,Microsoft.PowerShell.Commands.TestModuleManifestCommand"
    }

    It "module manifest containing empty rootmodule succeeds: <rootModuleValue>" -TestCases (
        @{rootModuleValue = $null},
        @{rootModuleValue = ""}
    ) {

        param($rootModuleValue)

        New-Item -ItemType Directory -Path testdrive:/module
        $testModulePath = "testdrive:/module/test.psd1"

        New-ModuleManifest -Path $testModulePath -RootModule $rootModuleValue
        $moduleManifest = Test-ModuleManifest -Path $testModulePath -ErrorAction Stop
        $moduleManifest | Should BeOfType System.Management.Automation.PSModuleInfo
        $moduleManifest.RootModule | Should BeNullOrEmpty
    }

    It "module manifest containing invalid rootmodule returns error: <rootModuleValue>" -TestCases (
        @{rootModuleValue = "foo.psd1"; error = "Modules_InvalidManifest"}
    ) {

        param($rootModuleValue, $error)

        $testModulePath = "testdrive:/module/test.psd1"
        New-Item -ItemType Directory -Path testdrive:/module
        New-Item -ItemType File -Path testdrive:/module/$rootModuleValue

        New-ModuleManifest -Path $testModulePath -RootModule $rootModuleValue
        { Test-ModuleManifest -Path $testModulePath -ErrorAction Stop } | ShouldBeErrorId "$error,Microsoft.PowerShell.Commands.TestModuleManifestCommand"
    }

    It "module manifest containing non-existing rootmodule returns error: <rootModuleValue>" -TestCases (
        @{rootModuleValue = "doesnotexist.psm1"; error = "Modules_InvalidRootModuleInModuleManifest"}
    ) {

        param($rootModuleValue, $error)

        $testModulePath = "testdrive:/module/test.psd1"
        New-Item -ItemType Directory -Path testdrive:/module

        New-ModuleManifest -Path $testModulePath -RootModule $rootModuleValue
        { Test-ModuleManifest -Path $testModulePath -ErrorAction Stop } | ShouldBeErrorId "$error,Microsoft.PowerShell.Commands.TestModuleManifestCommand"
    }
}


Describe "Tests for circular references in required modules" -tags "CI" {

    function CreateTestModules([string]$RootPath, [string[]]$ModuleNames, [bool]$AddVersion, [bool]$AddGuid, [bool]$AddCircularReference)
    {
        $RequiredModulesSpecs = @();
        foreach($moduleDir in New-Item $ModuleNames -ItemType Directory -Force)
        {
            if ($lastItem)
            {
                if ($AddVersion -or $AddGuid) {$RequiredModulesSpecs += $lastItem}
                else {$RequiredModulesSpecs += $lastItem.ModuleName}
            }

            $ModuleVersion = '3.0'
            $GUID = New-Guid

            New-ModuleManifest ((join-path $moduleDir.Name $moduleDir.Name) + ".psd1") -RequiredModules $RequiredModulesSpecs -ModuleVersion $ModuleVersion -Guid $GUID

            $lastItem = @{ ModuleName = $moduleDir.Name}
            if ($AddVersion) {$lastItem += @{ ModuleVersion = $ModuleVersion}}
            if ($AddGuid) {$lastItem += @{ GUID = $GUID}}
        }

        if ($AddCircularReference)
        {
            # rewrite first module's manifest to have a reference to the last module, i.e. making a circular reference
            if ($AddVersion -or $AddGuid)
            {
                $firstModuleName = $RequiredModulesSpecs[0].ModuleName
                $firstModuleVersion = $RequiredModulesSpecs[0].ModuleVersion
                $firstModuleGuid = $RequiredModulesSpecs[0].GUID
                $RequiredModulesSpecs = $lastItem
            }
            else
            {
                $firstModuleName = $RequiredModulesSpecs[0]
                $firstModuleVersion = '3.0' # does not matter - not used in references
                $firstModuleGuid = New-Guid # does not matter - not used in references
                $RequiredModulesSpecs = $lastItem.ModuleName
            }

            New-ModuleManifest ((join-path $firstModuleName $firstModuleName) + ".psd1") -RequiredModules $RequiredModulesSpecs -ModuleVersion $firstModuleVersion -Guid $firstModuleGuid
        }
    }

    function TestImportModule([bool]$AddVersion, [bool]$AddGuid, [bool]$AddCircularReference)
    {
        $moduleRootPath = Join-Path $TestDrive 'TestModules'
        New-Item $moduleRootPath -ItemType Directory -Force
        Push-Location $moduleRootPath

        $moduleCount = 6 # this depth was enough to find a bug in cyclic reference detection product code; greater depth will slow tests down
        $ModuleNames = 1..$moduleCount | ForEach-Object {"TestModule$_"}

        CreateTestModules $moduleRootPath $ModuleNames $AddVersion $AddGuid $AddCircularReference

        $newpath = [system.io.path]::PathSeparator + "$moduleRootPath"
        $OriginalPSModulePathLength = $env:PSModulePath.Length
        $env:PSModulePath += $newpath
        $lastModule = $ModuleNames[$moduleCount - 1]

        try
        {
            Import-Module $lastModule -ErrorAction Stop
            Get-Module $lastModule | Should Not BeNullOrEmpty
        }
        finally
        {
            #cleanup
            Remove-Module $ModuleNames -Force -ErrorAction SilentlyContinue
            $env:PSModulePath = $env:PSModulePath.Substring(0,$OriginalPSModulePathLength)
            Pop-Location
            Remove-Item $moduleRootPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "No circular references and RequiredModules field has only module names" {
        TestImportModule $false $false $false
    }

    It "No circular references and RequiredModules field has module names and versions" {
        TestImportModule $true $false $false
    }

    It "No circular references and RequiredModules field has module names, versions and GUIDs" {
        TestImportModule $true $true $false
    }

    It "Add a circular reference to RequiredModules and verify error" {
        { TestImportModule $false $false $true } | ShouldBeErrorId "Modules_InvalidManifest,Microsoft.PowerShell.Commands.ImportModuleCommand"
    }
}

Describe "Test-ModuleManifest Performance bug followup" -tags "CI" {
    BeforeAll {
        $TestModulesPath = [System.IO.Path]::Combine($PSScriptRoot, 'assets', 'testmodulerunspace')
        $UserModulesPath = "$pshome\Modules"

        # Install the Test Module
        Copy-Item $TestModulesPath\* $UserModulesPath -Recurse -Force
    }

    It "Test-ModuleManifest should not load unnessary modules" {

        $job = start-job -name "job1" -ScriptBlock {test-modulemanifest "$using:UserModulesPath\ModuleWithDependencies2\2.0\ModuleWithDependencies2.psd1" -verbose} | Wait-Job
        
        $verbose = $job.ChildJobs[0].Verbose.ReadAll()
        # Before the fix, all modules under $pshome will be imported and will be far more than 15 verbose messages. However, we cannot fix the number in case verbose message may vary.
        $verbose.Count | Should BeLessThan 15
    }

    AfterAll {
        #clean up the test modules
        Remove-Item $UserModulesPath\ModuleWithDependencies2 -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $UserModulesPath\NestedRequiredModule1 -Recurse -Force -ErrorAction SilentlyContinue
    }
}

