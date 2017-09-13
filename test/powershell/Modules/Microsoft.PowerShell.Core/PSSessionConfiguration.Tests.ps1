try
{
    # Skip all tests on non-windows and non-PowerShellCore and non-elevated platforms.
    $originalDefaultParameterValues = $PSDefaultParameterValues.Clone()
    $originalWarningPreference = $WarningPreference
    $WarningPreference = "SilentlyContinue"
    $IsNotSkipped = ($IsWindows -and $IsCoreCLR -and (Test-IsElevated))
    $PSDefaultParameterValues["it:skip"] = !$IsNotSkipped

    #
    # TODO: Enable-PSRemoting should be performed at a higher set up for all tests.
    # Tests whether PowerShell remoting is enabled for this instance of PowerShell.
    # If remoting is not enabled, it will enable it and then clean up after all the tests
    # have executed.
    #
    if ($IsNotSkipped)
    {
        $endpointName = "PowerShell.$($psversiontable.GitCommitId)"

        $matchedEndpoint = Get-PSSessionConfiguration $endpointName -ErrorAction SilentlyContinue

        if ($matchedEndpoint -eq $null)
        {
            # An endpoint for this instance of PowerShell does not exist.
            #
            # -SkipNetworkProfileCheck is used in case Docker or another application
            # has created a publich virtual network profile on the system
            Enable-PSRemoting -SkipNetworkProfileCheck
            $endpointCreated = $true
        }
    }

    try
    {
        Describe "Validate Register-PSSessionConfiguration" -Tags @("CI", 'RequireAdminOnWindows') {

            AfterAll {
                if ($IsNotSkipped)
                {
                    Get-PSSessionConfiguration -Name "ITTask*" -ErrorAction SilentlyContinue | Unregister-PSSessionConfiguration
                }
            }

            It "Register-PSSessionConfiguration -TransportOption" {

                $ConfigurationName = "ITTask" + (Get-Random -Minimum 10000 -Maximum 99999)
                $Transport = New-PSTransportOption -MaxSessions 40 -IdleTimeoutSec 3600

                $null = Register-PSSessionConfiguration -Name $ConfigurationName -TransportOption $Transport
                $result = Get-PSSessionConfiguration -Name $ConfigurationName

                $result.MaxShells | Should Be 40
                $result.IdleTimeoutms | Should Be 3600000
            }
        }
        Describe "Validate Get-PSSessionConfiguration, Enable-PSSessionConfiguration, Disable-PSSessionConfiguration, Unregister-PSSessionConfiguration cmdlets" -Tags @("CI", 'RequireAdminOnWindows') {

            BeforeAll {
                if ($IsNotSkipped)
                {
                    # Register new session configuration
                    function RegisterNewConfiguration {
                        param (

                            [string]
                            $Name,

                            [string]
                            $ConfigFilePath,

                            [switch]
                            $Enabled
                        )

                        $TestConfig = Get-PSSessionConfiguration -Name $Name -ErrorAction SilentlyContinue
                        if($TestConfig)
                        {
                            $null = Unregister-PSSessionConfiguration -Name $Name
                        }

                        if($Enabled)
                        {
                            $null = Register-PSSessionConfiguration -Name $Name -Path $ConfigFilePath
                        }
                        else
                        {
                            $null = Register-PSSessionConfiguration -Name $Name -Path $ConfigFilePath -AccessMode Disabled
                        }
                    }

                    # Unregister session configuration
                    function UnregisterPSSessionConfiguration{
                        param (

                            [string]
                            $Name
                        )

                        Unregister-PSSessionConfiguration -Name $Name -Force -NoServiceRestart -ErrorAction SilentlyContinue
                    }

                    # Create new Config File
                    function CreateTestConfigFile {

                        $TestConfigFileLoc = join-path $TestDrive "Remoting"
                        if(-not (Test-path $TestConfigFileLoc))
                        {
                            $null = New-Item -Path $TestConfigFileLoc -ItemType Directory -Force -ErrorAction Stop
                        }

                        $TestConfigFile = join-path $TestConfigFileLoc "TestConfigFile.pssc"
                        $null = New-PSSessionConfigurationFile -Path $TestConfigFile -SessionType Default

                        return $TestConfigFile
                    }

                    $LocalConfigFilePath = CreateTestConfigFile
                }
            }

            Context "Validate Get-PSSessionConfiguration cmdlet" {

                It "Get-PSSessionConfiguration with no parameter" {

                    $Result = Get-PSSessionConfiguration

                    $Result.Name -contains $endpointName | Should Be $true
                    $Result.PSVersion -ge 5.1 | Should be $true
                }

                It "Get-PSSessionConfiguration with Name parameter" {

                    $Result = Get-PSSessionConfiguration -Name $endpointName

                    $Result.Name | Should Be $endpointName
                    $Result.PSVersion -ge 5.1 | Should be $true
                }

                It "Get-PSSessionConfiguration -Name with wildcard character" {

                    $endpointWildcard = "powershell.*"

                    $Result = Get-PSSessionConfiguration -Name $endpointWildcard

                    $Result.Name -contains $endpointName | Should Be $true
                    $Result.PSVersion -ge 5.1 | Should be $true
                }

                It "Get-PSSessionConfiguration -Name with Non-Existent session configuration" {

                    try
                    {
                        Get-PSSessionConfiguration -Name "NonExistantSessionConfiguration" -ErrorAction Stop
                        throw "No Exception!"
                    }
                    catch
                    {
                        $_.FullyQualifiedErrorId | Should Be "Microsoft.PowerShell.Commands.WriteErrorException"
                    }
                }
            }

            Context "Validate Enable-PSSessionConfiguration and Disable-PSSessionConfiguration" {

                function VerifyEnableAndDisablePSSessionConfig {
                    param (
                        [string]
                        $SessionConfigName,

                        [string]
                        $ConfigFilePath,

                        [Bool]
                        $InitialSessionStateEnabled,

                        [Bool]
                        $FinalSessionStateEnabled,

                        [string]
                        $TestDescription,

                        [bool]
                        $EnablePSSessionConfig
                    )

                    It "$TestDescription" {

                        RegisterNewConfiguration -Name $SessionConfigName -ConfigFilePath $ConfigFilePath -Enabled:$InitialSessionStateEnabled

                        $TestConfigStateBeforeChange = (Get-PSSessionConfiguration -Name $SessionConfigName).Enabled

                        if($EnablePSSessionConfig)
                        {
                            $isSkipNetworkCheck = $true
                            # TODO: Get-NetConnectionProfile is not available during typical PS Core deployments. Once it is, this check should be used.
                            #Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq "Public" } | ForEach-Object { $isSkipNetworkCheck = $true }
                            Enable-PSSessionConfiguration -Name $SessionConfigName -NoServiceRestart -SkipNetworkProfileCheck:$isSkipNetworkCheck
                        }
                        else
                        {
                            Disable-PSSessionConfiguration -Name $SessionConfigName -NoServiceRestart
                        }

                        $TestConfigStateAfterChange = (Get-PSSessionConfiguration -Name $SessionConfigName -ErrorAction SilentlyContinue).Enabled

                        UnregisterPSSessionConfiguration -Name $SessionConfigName

                        $TestConfigStateBeforeChange | Should be "$InitialSessionStateEnabled"
                        $TestConfigStateAfterChange | Should be "$FinalSessionStateEnabled"
                    }
                }

                $TestData = @(
                    @{
                        SessionConfigName = "TestDisablePSSessionConfig"
                        ConfigFilePath = $LocalConfigFilePath
                        InitialSessionStateEnabled = $true
                        FinalSessionStateEnabled = $false
                        TestDescription = "Validate Disable-Configuration cmdlet"
                        EnablePSSessionConfig = $false
                    }

                    @{
                        SessionConfigName = "TestEnablePSSessionConfig"
                        ConfigFilePath = $LocalConfigFilePath
                        InitialSessionStateEnabled = $false
                        FinalSessionStateEnabled = $true
                        TestDescription = "Validate Enable-Configuration cmdlet"
                        EnablePSSessionConfig = $true
                    }
                )

                foreach ($testcase in $testData)
                {
                    VerifyEnableAndDisablePSSessionConfig @testcase
                }
            }

            Context "Validate Unregister-PSSessionConfiguration cmdlet" {

                BeforeEach {
                    Register-PSSessionConfiguration -Name "TestUnregisterPSSessionConfig"
                }

                AfterAll {
                    if ($IsNotSkipped)
                    {
                        Unregister-PSSessionConfiguration -name "TestUnregisterPSSessionConfig" -ErrorAction SilentlyContinue | Out-Null
                    }
                }

                function TestUnRegisterPSSsessionConfiguration {

                    param ($Description, $SessionConfigName, $ExpectedOutput, $ExpectedError)

                    It "$Description" {

                        $Result = [PSObject] @{Output = $true ; Error = $null}
                        $Error.Clear()
                        try
                        {
                            $null = Unregister-PSSessionConfiguration -name $SessionConfigName -ErrorAction stop
                        }
                        catch
                        {
                            $Result.Error = $_.Exception
                        }

                        if(-not $Result.Error)
                        {
                            $ValidEndpoints = [PSObject]@(Get-PSSessionConfiguration)

                            foreach ($endpoint in $ValidEndpoints)
                            {
                                # Setting it to false means the unregister was unsuccessful
                                # and there is still an endpoint with name matching the one we wanted to remove.
                                if($endpoint.name -like $SessionConfigName)
                                {
                                    $Result.Output = $false
                                    break
                                }
                            }
                        }
                        else
                        {
                            $Result.Output = $false
                        }

                        $Result.Output | Should Match $ExpectedOutput
                        $Result.Error | Should Match $ExpectedError
                    }
                }

                $TestData = @(
                    @{
                        Description = "Validate Unregister-PSSessionConfiguration with -name parameter"
                        SessionConfigName = "TestUnregisterPSSessionConfig"
                        ExpectedOutput = $true
                        ExpectedError = $null
                    }
                    @{
                        Description = "Validate Unregister-PSSessionConfiguration with name having wildcard character"
                        SessionConfigName = "TestUnregister*"
                        ExpectedOutput = $true
                        ExpectedError = $null
                    }
                    @{
                        Description = "Validate Unregister-PSSessionConfiguration for non-existant endpoint"
                        SessionConfigName = 'TestInvalidEndPoint'
                        ExpectedOutput = $false
                        ExpectedError = "No session configuration matches criteria `"TestInvalidEndPoint`"."
                    }
                )

                foreach ($TestCase in $TestData)
                {
                    TestUnRegisterPSSsessionConfiguration @TestCase
                }
            }
        }

        Describe "Validate Register-PSSessionConfiguration, Set-PSSessionConfiguration cmdlets" -Tags @("Feature", 'RequireAdminOnWindows') {

            BeforeAll {
                if ($IsNotSkipped)
                {
                    function ValidateRemoteEndpoint {
                        param ($TestSessionConfigName, $ScriptToExecute, $ExpectedOutput)

                        $Result = [PSObject]@{Output= $null; Error = $null}
                        try
                        {
                            $sn = New-PSSession . -ConfigurationName $TestSessionConfigName -ErrorAction Stop
                            if($sn)
                            {
                                if($ScriptToExecute)
                                {
                                    $Result.Output = invoke-command -Session $Sn -ScriptBlock { param ($scripttoExecute) Invoke-Expression $scripttoExecute} -ArgumentList $ScriptToExecute
                                }
                                else
                                {
                                    $Result.Output = $true
                                }
                            }
                            else
                            {
                                throw "Unable to create session $TestSessionConfigName"
                            }
                        }
                        catch
                        {
                            $Result.Error = $_.Error.FullyQualifiedErrorId
                        }
                        finally
                        {
                            if ($sn)
                            {
                                Remove-PSSession $sn -ErrorAction SilentlyContinue | Out-Null
                                $sn = $null
                            }
                        }
                        $Result.Output | Should be $ExpectedOutput
                        $Result.Error | Should be $null
                    }

                    # Create Test Startup Script
                    function CreateStartupScript {
                        $ScriptContent = @"
`$script:testvariable = "testValue"
"@

                        $TestScript = join-path $script:TestDir "StartupTestScript.ps1"
                        $null = Set-Content -path $TestScript -Value $ScriptContent

                        return $TestScript
                    }

                    # Create new Config File
                    function CreateTestConfigFile {

                        $TestConfigFile = join-path $script:TestDir "TestConfigFile.pssc"
                        $null = New-PSSessionConfigurationFile -Path $TestConfigFile -SessionType Default
                        return $TestConfigFile
                    }

                    function CreateTestModule {
                        $ScriptContent = @"
function IsTestModuleImported {
return `$true
}
Export-ModuleMember IsTestModuleImported
"@
                        $TestModuleFileLoc = $script:TestDir

                        if(-not (Test-path $TestModuleFileLoc))
                        {
                            $null = New-Item -Path $TestModuleFileLoc -ItemType Directory -Force -ErrorAction Stop
                        }

                        $TestModuleFile = join-path $TestModuleFileLoc "TestModule.psm1"
                        $null = Set-Content -path $TestModuleFile -Value $ScriptContent

                        return $TestModuleFile
                    }

                    function CreateTestAssembly {
                        $PscConfigDef = @"
using System;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Management.Automation.Remoting;

namespace PowershellTestConfigNamespace
{
    public sealed class PowershellTestConfig : PSSessionConfiguration
    {
        /// <summary>
        ///
        /// </summary>
        /// <param name="senderInfo"></param>
        /// <returns></returns>
        public override InitialSessionState GetInitialSessionState(PSSenderInfo senderInfo)
        {
            return InitialSessionState.CreateDefault();
        }

    }
}
"@
                        $script:SourceFile = join-path $script:TestAssemblyDir "PowershellTestConfig.cs"
                        $PscConfigDef | out-file $script:SourceFile -Encoding ascii -Force
                        $TestAssemblyName = "TestAssembly.dll"
                        $TestAssemblyPath = join-path $script:TestAssemblyDir $TestAssemblyName
                        Add-Type -path $script:SourceFile -OutputAssembly $TestAssemblyPath
                        return $TestAssemblyName
                    }

                    $script:TestDir = join-path $TestDrive "Remoting"
                    if(-not (Test-Path $script:TestDir))
                    {
                        $null = New-Item -path $script:TestDir -ItemType Directory
                    }

                    $script:TestAssemblyDir = [System.IO.Path]::GetTempPath()
                    if(-not (Test-Path $script:TestAssemblyDir))
                    {
                        $null = New-Item -path $script:TestAssemblyDir -ItemType Directory
                    }

                    $LocalConfigFilePath = CreateTestConfigFile
                    $LocalStartupScriptPath = CreateStartupScript
                    $LocalTestModulePath = CreateTestModule
                    $LocalTestAssemblyName = CreateTestAssembly
                    $LocalTestDir = $script:TestDir
                }
            }

            AfterAll {
                if ($IsNotSkipped)
                {
                    Remove-Item $LocalTestDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            Context "Validate Register-PSSessionConfiguration" {

                BeforeAll {
                    if ($IsNotSkipped)
                    {
                        $TestSessionConfigName = "TestRegisterPSSesionConfig"
                        Unregister-PSSessionConfiguration -Name $TestSessionConfigName -Force -NoServiceRestart -ErrorAction SilentlyContinue
                    }
                }

                AfterEach {
                    Unregister-PSSessionConfiguration -Name $TestSessionConfigName -Force -NoServiceRestart -ErrorAction SilentlyContinue
                }

                It "Validate Register-PSSessionConfiguration -name -path" {

                    $pssessionthreadoptions = "UseCurrentThread"
                    $psmaximumreceivedobjectsizemb = 20
                    $psmaximumreceiveddatasizepercommandmb = 20
                    $UseSharedProcess = $true

                    Register-PSSessionConfiguration -Name $TestSessionConfigName -path $LocalConfigFilePath -MaximumReceivedObjectSizeMB $psmaximumreceivedobjectsizemb -MaximumReceivedDataSizePerCommandMB $psmaximumreceiveddatasizepercommandmb -UseSharedProcess:$UseSharedProcess -ThreadOptions $pssessionthreadoptions
                    $Result = [PSObject]@{Session = Get-PSSessionConfiguration -Name $TestSessionConfigName; Culture = (Get-Item WSMan:\localhost\Plugin\$endpointName\lang -ea SilentlyContinue).value}

                    $Result.Session.Name | Should be $TestSessionConfigName
                    $Result.Session.SessionType | Should be "Default"
                    $Result.Session.PSVersion | Should be 6.0
                    $Result.Session.Enabled | Should be $true
                    $Result.Session.lang | Should be $Result.Culture
                    $Result.Session.pssessionthreadoptions | Should be $pssessionthreadoptions
                    $Result.Session.psmaximumreceivedobjectsizemb | Should be $psmaximumreceivedobjectsizemb
                    $Result.Session.psmaximumreceiveddatasizepercommandmb | Should be $psmaximumreceiveddatasizepercommandmb
                    $Result.Session.UseSharedProcess | Should be $UseSharedProcess
                }

                It "Validate Register-PSSessionConfiguration -startupscript parameter" -Pending {

                    $null = Register-PSSessionConfiguration -Name $TestSessionConfigName -path $LocalConfigFilePath -StartupScript $LocalStartupScriptPath -Force

                    ValidateRemoteEndpoint -TestSessionConfigName $TestSessionConfigName -ScriptToExecute "return `$script:testvariable" -ExpectedOutput "testValue" -ExpectedError $null
                }


                It "Validate Register-PSSessionConfiguration -AccessMode parameter" {

                    $null = Register-PSSessionConfiguration -Name $TestSessionConfigName -path $LocalConfigFilePath -AccessMode Disabled -Force

                    ValidateRemoteEndpoint -TestSessionConfigName $TestSessionConfigName -ScriptToExecute $null -ExpectedOutput $null -ExpectedError "RemoteConnectionDisallowed,PSSessionOpenFailed"
                }


                It "Validate Register-PSSessionConfiguration -ModulesToImport parameter" -Pending {

                    $null = Register-PSSessionConfiguration -Name $TestSessionConfigName -ModulesToImport $LocalTestModulePath -Force

                    ValidateRemoteEndpoint -TestSessionConfigName $TestSessionConfigName -ScriptToExecute "return IsTestModuleImported" -ExpectedOutput $true -ExpectedError $null
                }

                It "Validate Register-PSSessionConfiguration with ApplicationBase, AssemblyName and ConfigurationTypeName parameter" -Pending {

                    $null = Register-PSSessionConfiguration -Name $TestSessionConfigName -ApplicationBase $script:TestAssemblyDir -AssemblyName $LocalTestAssemblyName -ConfigurationTypeName "PowershellTestConfigNamespace.PowershellTestConfig" -force

                    ValidateRemoteEndpoint -TestSessionConfigName $TestSessionConfigName -ScriptToExecute $null -ExpectedOutput $true -ExpectedError $null
                }
            }

            Context "Validate Set-PSSessionConfiguration" {

                BeforeAll {
                    if ($IsNotSkipped)
                    {
                        $TestSessionConfigName = "TestSetPSSesionConfig"
                        Unregister-PSSessionConfiguration -Name $TestSessionConfigName -Force -NoServiceRestart -ErrorAction SilentlyContinue
                    }
                }

                AfterEach {
                    Unregister-PSSessionConfiguration -Name $TestSessionConfigName -Force -NoServiceRestart -ErrorAction SilentlyContinue
                }

                BeforeEach {
                    Register-PSSessionConfiguration -Name $TestSessionConfigName
                }

                It "Validate Set-PSSessionConfiguration -name -path -MaximumReceivedObjectSizeMB -MaximumReceivedDataSizePerCommandMB -UseSharedProcess -ThreadOptions parameters" {

                    $pssessionthreadoptions = "UseCurrentThread"
                    $psmaximumreceivedobjectsizemb = 20
                    $psmaximumreceiveddatasizepercommandmb = 20
                    $UseSharedProcess = $true

                    Set-PSSessionConfiguration -Name $TestSessionConfigName -MaximumReceivedObjectSizeMB $psmaximumreceivedobjectsizemb -MaximumReceivedDataSizePerCommandMB $psmaximumreceiveddatasizepercommandmb -UseSharedProcess:$UseSharedProcess -ThreadOptions $pssessionthreadoptions -NoServiceRestart
                    $Result = [PSObject]@{Session = (Get-PSSessionConfiguration -Name $TestSessionConfigName) ; Culture = (Get-Item WSMan:\localhost\Plugin\microsoft.powershell\lang -ea SilentlyContinue).value}

                    $Result.Session.Name | Should be $TestSessionConfigName
                    $Result.Session.PSVersion | Should be 6.0
                    $Result.Session.Enabled | Should be $true
                    $Result.Session.lang | Should be $result.Culture
                    $Result.Session.pssessionthreadoptions | Should be $pssessionthreadoptions
                    $Result.Session.psmaximumreceivedobjectsizemb | Should be $psmaximumreceivedobjectsizemb
                    $Result.Session.psmaximumreceiveddatasizepercommandmb | Should be $psmaximumreceiveddatasizepercommandmb
                    $Result.Session.UseSharedProcess | Should be $UseSharedProcess
                }

                It "Validate Set-PSSessionConfiguration -startupscript parameter" -Pending {

                    $null = Set-PSSessionConfiguration -Name $TestSessionConfigName -StartupScript $LocalStartupScriptPath

                    ValidateRemoteEndpoint -TestSessionConfigName $TestSessionConfigName -ScriptToExecute "return `$script:testvariable" -ExpectedOutput "testValue" -ExpectedError $null
                }

                It "Validate Set-PSSessionConfiguration -AccessMode parameter" {

                    $null = Set-PSSessionConfiguration -Name $TestSessionConfigName -AccessMode Disabled

                    ValidateRemoteEndpoint -TestSessionConfigName $TestSessionConfigName -ScriptToExecute $null -ExpectedOutput $null -ExpectedError "RemoteConnectionDisallowed,PSSessionOpenFailed"
                }

                It "Validate Set-PSSessionConfiguration -ModulesToImport parameter" -Pending {

                    $null = Set-PSSessionConfiguration -Name $TestSessionConfigName -ModulesToImport $LocalTestModulePath -Force

                    ValidateRemoteEndpoint -TestSessionConfigName $TestSessionConfigName -ScriptToExecute "return IsTestModuleImported" -ExpectedOutput $true -ExpectedError $null
                }

                It "Validate Set-PSSessionConfiguration with ApplicationBase, AssemblyName and ConfigurationTypeName parameter" -Pending {

                    $null = Set-PSSessionConfiguration -Name $TestSessionConfigName -ApplicationBase $script:TestAssemblyDir -AssemblyName $LocalTestAssemblyName -ConfigurationTypeName "PowershellTestConfigNamespace.PowershellTestConfig" -force

                    ValidateRemoteEndpoint -TestSessionConfigName $TestSessionConfigName -ScriptToExecute $null -ExpectedOutput $true -ExpectedError $null
                }
            }
        }
    }
    finally
    {
        if ($endpointCreated)
        {
            Get-PSSessionConfiguration $endpointName -ErrorAction SilentlyContinue | Unregister-PSSessionConfiguration
        }
    }

    Describe "Basic tests for New-PSSessionConfigurationFile Cmdlet" -Tags @("CI", 'RequireAdminOnWindows') {

        It "Validate New-PSSessionConfigurationFile can successfully create a valid PSSessionConfigurationFile" {

            $configFilePath = join-path $TestDrive "SamplePSSessionConfigurationFile.pssc"
            try
            {
                New-PSSessionConfigurationFile $configFilePath
                $result = get-content $configFilePath | Out-String
            }
            finally
            {
                if(Test-Path $configFilePath){ Remove-Item $configFilePath -Force }
            }

            $resultContent = invoke-expression ($result)
            $resultContent.GetType().ToString() | Should Be "System.Collections.Hashtable"

            # The default created hashtable in the session configuration file would have the
            # following keys which we are validating below.
            $resultContent.ContainsKey("SessionType") -and $resultContent.ContainsKey("SchemaVersion") -and $resultContent.ContainsKey("Guid") -and $resultContent.ContainsKey("Author") | Should Be $true
        }
    }

    Describe "Feature tests for New-PSSessionConfigurationFile Cmdlet" -Tags @("Feature", 'RequireAdminOnWindows') {

        It "Validate FullyQualifiedErrorId from New-PSSessionConfigurationFile when invalid path is provided as input" {

            try
            {
                $filePath = "cert:\foo.pssc"
                New-PSSessionConfigurationFile $filePath
                throw "No Exception!"
            }
            catch
            {
                $_.FullyQualifiedErrorId | Should Be "InvalidPSSessionConfigurationFilePath,Microsoft.PowerShell.Commands.NewPSSessionConfigurationFileCommand"
            }
        }
    }

    Describe "Test suite for Test-PSSessionConfigurationFile Cmdlet" -Tags @("CI", 'RequireAdminOnWindows') {

        BeforeAll {
            if ($IsNotSkipped)
            {
                $parmMap = @{
                    # values for PSSessionConfigFile
                    PowerShellVersion = '3.0'
                    SessionType = 'Default'
                    Author = 'User'
                    CompanyName = 'Microsoft Corporation'
                    Copyright = 'Copyright (c) 2011 Microsoft Corporation. All rights reserved.'
                    Description = 'This is a sample session configuration file.'
                    GUID = '73cba863-aa49-4cbf-9917-269ddcf2b1e3'
                    SchemaVersion = '1.0.0.0'

                    # The scope of the test is to validate that a valid SessionConfigurationFile can be validated
                    # The test does not register the session configuration from the created session configuration file.
                    # The SCRATCH location is not validated.
                    EnvironmentVariables = @{
                        PSModulePath = '$Env:PSModulePath + ";$env:SystemDrive\ProgramData"';
                        SCRATCH = "\\SomeValidRemoteShare\SharedLocation"
                    }

                    # The scope of the test is to validate that a valid SessionConfigurationFile can be validated
                    # The test does not register the session configuration from the created session configuration file.
                    # The AssembliesToLoad are not loaded by this test. The Test only validates that the supplied data
                    # is used to create a valid Session configuration file.
                    AssembliesToLoad = 'SomeValidBinary.dll'

                    # The same explanation as above holds good here.
                    ModulesToImport = 'SomeValidModule'
                    AliasDefinitions = @(
                        @{
                            Name = "gh";
                            Value = "Get-Help";
                            Description = "Gets the help";
                            Options = "AllScope";
                        },
                        @{
                            Name = "sh";
                            Value = "Save-Help";
                            Description = "Saves the help";
                            Options = "Private";
                        },
                        @{
                            Name = "uh";
                            Value = "Update-Help";
                            Description = "Updates the help";
                            Options = "ReadOnly";
                        }
                    )
                    FunctionDefinitions=@(
                        @{
                            Name = "sysmodules";
                            ScriptBlock = 'pushd $pshome\Modules';
                            Options = "AllScope";
                        },
                        @{
                            Name = "mymodules";
                            ScriptBlock = 'pushd $home\Documents\WindowsPowerShell\Modules';
                            Options = "ReadOnly";
                        }
                    )
                    VariableDefinitions = @(
                        @{
                            Name = "WarningPreference";
                            Value = "SilentlyContinue";
                        },
                        @{
                            Name = "datahome";
                            Value = "\\fileserver\share\data";
                        },
                        @{
                            Name = "allusershome";
                            Value = '$env:ProgramData'
                        }
                    )

                    # The scope of the test is to validate that a valid SessionConfigurationFile can be validated
                    # The test does not register the session configuration from the created session configuration file.
                    # The existance of the files supplied as input to TypesToProcess, FormatsToProcess, ScriptsToProcess
                    # are not validated while creating a valid session configurtation file.
                    # The Test only validates that the supplied data can be successfully used to create a valid Session configuration file.
                    TypesToProcess = '$env:SystemDrive\SampleTypesFile.ps1xml'
                    FormatsToProcess = '$env:SystemDrive\SampleFormatsFile.ps1xml'
                    ScriptsToProcess = '$env:SystemDrive\SampleScript.ps1'
                    VisibleAliases = "c*","g*","i*","s*"
                    VisibleCmdlets = "c*","get*","i*","set*"
                    VisibleFunctions = "*"
                    VisibleProviders = 'FileSystem','Function','Registry','Variable'
                    VisibleVariables = "*"
                    LanguageMode = "RestrictedLanguage"
                    ExecutionPolicy = "AllSigned"
                }
            }
        }

        It "Validate FullyQualifiedErrorId from Test-PSSessionConfigurationFile when invalid path is provided as input" {

            try
            {
                Test-PSSessionConfigurationFile "cert:\foo.pssc" -ErrorAction Stop
                throw "No Exception!"
            }
            catch
            {
                $_.FullyQualifiedErrorId | Should Be "PSSessionConfigurationFileNotFound,Microsoft.PowerShell.Commands.TestPSSessionConfigurationFileCommand"
            }
        }

        It "Validate FullyQualifiedErrorId from Test-PSSessionConfigurationFile when an invalid pssc file is provided as input and -Verbose parameter is specified" {

            $configFilePath = join-path $TestDrive "SamplePSSessionConfigurationFile.pssc"
            "InvalidData" | Out-File $configFilePath

            Test-PSSessionConfigurationFile $configFilePath -Verbose -ErrorAction Stop | Should Be $false
        }

        It "Test case verifies that the generated config file passes validation" {

            # Path the config file
            $configFilePath = join-path $TestDrive "SamplePSSessionConfigurationFile.pssc"

            $updatedFunctionDefn = @()
            foreach($currentDefination in $parmMap.FunctionDefinitions)
            {
                $createdFunctionDefn = @{}
                foreach($currentDefinationKey in $currentDefination.Keys)
                {
                    if($currentDefinationKey -eq "ScriptBlock")
                    {
                        $value = [ScriptBlock]::Create($currentDefination[$currentDefinationKey])
                    }
                    else
                    {
                        $value = $currentDefination[$currentDefinationKey]
                    }
                    $createdFunctionDefn.Add($currentDefinationKey, $value)
                }
            $updatedFunctionDefn += $createdFunctionDefn
            }

            $updatedVariableDefn = @()
            foreach($currentDefination in $parmMap.VariableDefinitions)
            {
                $createdVariableDefn = @{}
                foreach($currentDefinationKey in $currentDefination.Keys)
                {
                    $createdVariableDefn.Add($currentDefinationKey, $currentDefination[$currentDefinationKey])
                }
            $updatedVariableDefn += $createdVariableDefn
            }

            try
            {
                # Create Config file
                New-PSSessionConfigurationFile `
                -Path $configFilePath `
                -SchemaVersion $parmMap.SchemaVersion `
                -Author $parmMap.Author `
                -CompanyName $parmMap.CompanyName `
                -Copyright $parmMap.Copyright `
                -Description $parmMap.Description `
                -PowerShellVersion $parmMap.PowerShellVersion `
                -SessionType  $parmMap.SessionType  `
                -ModulesToImport $parmMap.ModulesToImport `
                -AssembliesToLoad $parmMap.AssembliesToLoad `
                -VisibleAliases $parmMap.VisibleAliases `
                -VisibleCmdlets $parmMap.VisibleCmdlets `
                -VisibleFunctions $parmMap.VisibleFunctions `
                -VisibleProviders $parmMap.VisibleProviders `
                -AliasDefinitions $parmMap.AliasDefinitions `
                -FunctionDefinitions $updatedFunctionDefn `
                -VariableDefinitions $updatedVariableDefn `
                -EnvironmentVariables $parmMap.EnvironmentVariables `
                -TypesToProcess $parmMap.TypesToProcess `
                -FormatsToProcess $parmMap.FormatsToProcess `
                -LanguageMode $parmMap.LanguageMode `
                -ExecutionPolicy $parmMap.ExecutionPolicy `
                -ScriptsToProcess $parmMap.ScriptsToProcess `
                -GUID $parmMap.GUID

                # Verify the generated config file using the Test-PSSessionConfigurationFile
                $result = Test-PSSessionConfigurationFile -Path $configFilePath -Verbose
            }

            finally
            {
                if(Test-Path $configFilePath)
                {
                    Remove-Item $configFilePath -Force
                }
            }

            $result | Should Be $true
        }
    }
}
finally
{
    $global:PSDefaultParameterValues = $originalDefaultParameterValues
    $WarningPreference = $originalWarningPreference
}

