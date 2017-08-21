$ErrorActionPreference = 'Stop'
$repoRoot = Join-Path $PSScriptRoot '..'
$script:administratorsGroupSID = "S-1-5-32-544"
$script:usersGroupSID = "S-1-5-32-545"

$dotNetPath = "$env:USERPROFILE\Appdata\Local\Microsoft\dotnet"
if(Test-Path $dotNetPath)
{
    $env:PATH = $dotNetPath + ';' + $env:PATH
}

#import build into the global scope so it can be used by packaging
Import-Module (Join-Path $repoRoot 'build.psm1') -Scope Global
Import-Module (Join-Path $repoRoot 'tools\packaging')

function New-LocalUser
{
  <#
    .SYNOPSIS
        Creates a local user with the specified username and password
    .DESCRIPTION
    .EXAMPLE
    .PARAMETER
        username Username of the user which will be created
    .PARAMETER
        password Password of the user which will be created
    .OUTPUTS
    .NOTES
  #>
  param(
    [Parameter(Mandatory=$true)]
    [string] $username,

    [Parameter(Mandatory=$true)]
    [string] $password

  )

  $LocalComputer = [ADSI] "WinNT://$env:computername";
  $user = $LocalComputer.Create('user', $username);
  $user.SetPassword($password) | out-null;
  $user.SetInfo() | out-null;
}

<#
  Converts SID to NT Account Name
#>
function ConvertTo-NtAccount
{
  param(
    [Parameter(Mandatory=$true)]
    [string] $sid
  )
	(new-object System.Security.Principal.SecurityIdentifier($sid)).translate([System.Security.Principal.NTAccount]).Value
}

<#
  Add a user to a local security group
#>
function Add-UserToGroup
{
  param(
    [Parameter(Mandatory=$true)]
    [string] $username,

    [Parameter(Mandatory=$true, ParameterSetName = "SID")]
    [string] $groupSid,

    [Parameter(Mandatory=$true, ParameterSetName = "Name")]
    [string] $group
  )

  $userAD = [ADSI] "WinNT://$env:computername/${username},user"

  if($PsCmdlet.ParameterSetName -eq "SID")
  {
    $ntAccount=ConvertTo-NtAccount $groupSid
    $group =$ntAccount.Split("\\")[1]
  }

  $groupAD = [ADSI] "WinNT://$env:computername/${group},group"

  $groupAD.Add($userAD.AdsPath);
}


# tests if we should run a daily build
# returns true if the build is scheduled
# or is a pushed tag
Function Test-DailyBuild
{
    $trueString = 'True'
    if(($env:PS_DAILY_BUILD -eq $trueString) -or ($env:APPVEYOR_SCHEDULED_BUILD -eq $trueString) -or ($env:APPVEYOR_REPO_TAG_NAME))
    {
        return $true
    }
    
    # if [Feature] is in the commit message,
    # Run Daily tests
    if($env:APPVEYOR_REPO_COMMIT_MESSAGE -match '\[feature\]')
    {
        Set-AppveyorBuildVariable -Name PS_DAILY_BUILD -Value $trueString
        return $true
    }

    return $false
}

# Sets a build variable
Function Set-BuildVariable
{
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $Name,

        [Parameter(Mandatory=$true)]
        [string]
        $Value
    )

    if($env:AppVeyor)
    {
        Set-AppveyorBuildVariable @PSBoundParameters
    }
    else
    {
        Set-Item env:/$name -Value $Value
    }
}

# Emulates running all of AppVeyor but locally
# should not be used on AppVeyor
function Invoke-AppVeyorFull
{
    param(
        [switch] $APPVEYOR_SCHEDULED_BUILD,
        [switch] $CleanRepo
    )
    if($CleanRepo)
    {
        Clear-PSRepo
    }

    if($env:APPVEYOR)
    {
        throw "This function is to simulate appveyor, but not to be run from appveyor!"
    }

    if($APPVEYOR_SCHEDULED_BUILD)
    {
        $env:APPVEYOR_SCHEDULED_BUILD = 'True'
    }
    try {
        Invoke-AppVeyorInstall
        Invoke-AppVeyorBuild
        Invoke-AppVeyorTest -ErrorAction Continue
        Invoke-AppveyorFinish
    }
    finally {
        if($APPVEYOR_SCHEDULED_BUILD -and $env:APPVEYOR_SCHEDULED_BUILD)
        {
            Remove-Item env:APPVEYOR_SCHEDULED_BUILD
        }
    }
}

# Implements the AppVeyor 'build_script' step
function Invoke-AppVeyorBuild
{
      # check to be sure our test tags are correct
      $result = Get-PesterTag
      if ( $result.Result -ne "Pass" ) {
        $result.Warnings
        throw "Tags must be CI, Feature, Scenario, or Slow"
      }

      if(Test-DailyBuild)
      {
          Start-PSBuild -Configuration 'CodeCoverage' -PSModuleRestore
      }

      Start-PSBuild -CrossGen -PSModuleRestore -Configuration 'Release'
}

# Implements the AppVeyor 'install' step
function Invoke-AppVeyorInstall
{
    # Make sure we have all the tags
    Sync-PSTags -AddRemoteIfMissing
    if($env:APPVEYOR_BUILD_NUMBER)
    {
        Update-AppveyorBuild -Version "$(Get-PSVersion -OmitCommitId)-$env:APPVEYOR_BUILD_NUMBER"
    }

    if(Test-DailyBuild){
        $buildName = "[Daily]"

        # Add daily to title if it's not already there
        # It can be there already for rerun requests
        if($env:APPVEYOR_PULL_REQUEST_TITLE -and $env:APPVEYOR_PULL_REQUEST_TITLE  -notmatch '^\[Daily\]')
        {
            $buildName += $env:APPVEYOR_PULL_REQUEST_TITLE
        }
        elseif($env:APPVEYOR_PULL_REQUEST_TITLE)
        {
            $buildName = $env:APPVEYOR_PULL_REQUEST_TITLE
        }
        elseif($env:APPVEYOR_REPO_COMMIT_MESSAGE -notmatch '^\[Daily\].*$')
        {
            
            $buildName += $env:APPVEYOR_REPO_COMMIT_MESSAGE
        }
        else
        {
            $buildName = $env:APPVEYOR_REPO_COMMIT_MESSAGE
        }

        Update-AppveyorBuild -message $buildName
    }

    if ($env:APPVEYOR)
    {
        #
        # Generate new credential for appveyor (only) remoting tests.
        #
        Write-Verbose "Creating account for remoting tests in AppVeyor."

        # Password
        $randomObj = [System.Random]::new()
        $password = ""
        1..(Get-Random -Minimum 15 -Maximum 126) | ForEach-Object { $password = $password + [char]$randomObj.next(45,126) }

        # Account
        $userName = 'appVeyorRemote'
        New-LocalUser -username $userName -password $password
        Add-UserToGroup -username $userName -groupSid $script:administratorsGroupSID

        # Provide credentials globally for remote tests.
        $ss = ConvertTo-SecureString -String $password -AsPlainText -Force
        $appveyorRemoteCredential = [PSCredential]::new("$env:COMPUTERNAME\$userName", $ss)
	    $appveyorRemoteCredential | Export-Clixml -Path "$env:TEMP\AppVeyorRemoteCred.xml" -Force

        # Check that LocalAccountTokenFilterPolicy policy is set, since it is needed for remoting
        # using above local admin account.
        Write-Verbose "Checking for LocalAccountTokenFilterPolicy in AppVeyor."
        $haveLocalAccountTokenFilterPolicy = $false
        try
        {
            $haveLocalAccountTokenFilterPolicy = ((Get-ItemPropertyValue -Path HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name LocalAccountTokenFilterPolicy) -eq 1)
        }
        catch { }
        if (!$haveLocalAccountTokenFilterPolicy)
        {
            Write-Verbose "Setting the LocalAccountTokenFilterPolicy for remoting tests"
            Set-ItemProperty -Path HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name LocalAccountTokenFilterPolicy -Value 1
        }
    }

    Set-BuildVariable -Name TestPassed -Value False
    Start-PSBootstrap -Confirm:$false
}

# A wrapper to ensure that we upload test results
# and that if we are not able to that it does not fail
# the CI build
function Update-AppVeyorTestResults
{
    param(
        [string] $resultsFile
    )

    if($env:Appveyor)
    {
        $retryCount = 0
        $pushedResults = $false
        $pushedArtifacts = $false
        while( (!$pushedResults -or !$pushedResults) -and $retryCount -lt 3)
        {
            if($retryCount -gt 0)
            {
                Write-Verbose "Retrying updating test artifacts..."
            }

            $retryCount++
            $resolvedResultsPath = (Resolve-Path $resultsFile)
            try {
                (New-Object 'System.Net.WebClient').UploadFile("https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)", $resolvedResultsPath)
                $pushedResults = $true
            }
            catch {
                Write-Warning "Pushing test result failed..."
            }

            try {
                Push-AppveyorArtifact $resolvedResultsPath
                $pushedArtifacts = $true
            }
            catch {
                Write-Warning "Pushing test Artifact failed..."
            }
        }

        if(!$pushedResults -or !$pushedResults)
        {
            Write-Warning "Failed to push all artifacts for $resultsFile"
        }
    }
    else
    {
        Write-Warning "Not running in appveyor, skipping upload of test results: $resultsFile"
    }
}

# Implement AppVeyor 'Test_script'
function Invoke-AppVeyorTest
{
    [CmdletBinding()]
    param()
    #
    # CoreCLR

    $env:CoreOutput = Split-Path -Parent (Get-PSOutput -Options (New-PSOptions -Configuration 'Release'))
    Write-Host -Foreground Green 'Run CoreCLR tests'
    $testResultsNonAdminFile = "$pwd\TestsResultsNonAdmin.xml"
    $testResultsAdminFile = "$pwd\TestsResultsAdmin.xml"
    if(!(Test-Path "$env:CoreOutput\powershell.exe"))
    {
        throw "CoreCLR PowerShell.exe was not built"
    }

    if(-not (Test-DailyBuild))
    {
        # Pester doesn't allow Invoke-Pester -TagAll@('CI', 'RequireAdminOnWindows') currently
        # https://github.com/pester/Pester/issues/608
        # To work-around it, we exlude all categories, but 'CI' from the list
        $ExcludeTag = @('Slow', 'Feature', 'Scenario')
        Write-Host -Foreground Green 'Running "CI" CoreCLR tests..'
    }
    else
    {
        $ExcludeTag = @()
        Write-Host -Foreground Green 'Running all CoreCLR tests..'
    }

    # Remove telemetry semaphore file in CI
    $telemetrySemaphoreFilepath = Join-Path $env:CoreOutput DELETE_ME_TO_DISABLE_CONSOLEHOST_TELEMETRY
    if ( Test-Path "${telemetrySemaphoreFilepath}" ) {
        Remove-Item -Force ${telemetrySemaphoreFilepath}
    }

    Start-PSPester -bindir $env:CoreOutput -outputFile $testResultsNonAdminFile -Unelevate -Tag @() -ExcludeTag ($ExcludeTag + @('RequireAdminOnWindows'))
    Write-Host -Foreground Green 'Upload CoreCLR Non-Admin test results'
    Update-AppVeyorTestResults -resultsFile $testResultsNonAdminFile

    Start-PSPester -bindir $env:CoreOutput -outputFile $testResultsAdminFile -Tag @('RequireAdminOnWindows') -ExcludeTag $ExcludeTag
    Write-Host -Foreground Green 'Upload CoreCLR Admin test results'
    Update-AppVeyorTestResults -resultsFile $testResultsAdminFile

    #
    # Fail the build, if tests failed
    @(
        $testResultsNonAdminFile,
        $testResultsAdminFile
    ) | ForEach-Object {
        Test-PSPesterResults -TestResultsFile $_
    }

    Set-BuildVariable -Name TestPassed -Value True
}

#Implement AppVeyor 'after_test' phase
function Invoke-AppVeyorAfterTest
{
    [CmdletBinding()]
    param()

    if(Test-DailyBuild)
    {
        ## Publish code coverage build, tests and OpenCover module to artifacts, so webhook has the information.
        ## Build webhook is called after 'after_test' phase, hence we need to do this here and not in AppveyorFinish.
        $codeCoverageOutput = Split-Path -Parent (Get-PSOutput -Options (New-PSOptions -Configuration CodeCoverage))
        $codeCoverageArtifacts = Compress-CoverageArtifacts -CodeCoverageOutput $codeCoverageOutput

        Write-Host -ForegroundColor Green 'Upload CodeCoverage artifacts'
        $codeCoverageArtifacts | ForEach-Object { Push-AppveyorArtifact $_ }
    }
}

function Compress-CoverageArtifacts
{
    param([string] $CodeCoverageOutput)

    # Create archive for test content, OpenCover module and CodeCoverage build
    $artifacts = New-Object System.Collections.ArrayList

    $zipTestContentPath = Join-Path $pwd 'tests.zip'
    Compress-TestContent -Destination $zipTestContentPath
    $null = $artifacts.Add($zipTestContentPath)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Join-Path $PSScriptRoot '..\test\tools\OpenCover'))
    $zipOpenCoverPath = Join-Path $pwd 'OpenCover.zip'
    [System.IO.Compression.ZipFile]::CreateFromDirectory($resolvedPath, $zipOpenCoverPath)
    $null = $artifacts.Add($zipOpenCoverPath)

    $zipCodeCoveragePath = Join-Path $pwd "CodeCoverage.zip"
    Write-Verbose "Zipping ${CodeCoverageOutput} into $zipCodeCoveragePath" -verbose
    [System.IO.Compression.ZipFile]::CreateFromDirectory($CodeCoverageOutput, $zipCodeCoveragePath)
    $null = $artifacts.Add($zipCodeCoveragePath)

    return $artifacts
}

function Get-PackageName
{
    $name = git describe
    # Remove 'v' from version, prepend 'PowerShell' - to be consistent with other package names
    $name = $name -replace 'v',''
    $name = 'PowerShell_' + $name
    return $name
}

# Implements AppVeyor 'on_finish' step
function Invoke-AppveyorFinish
{
    try {
        $packageParams = @{}
        if($env:APPVEYOR_BUILD_VERSION)
        {
            $packageParams += @{Version=$env:APPVEYOR_BUILD_VERSION}
        }

        # Build packages
        $packages = Start-PSPackage @packageParams -SkipReleaseChecks

        $name = Get-PackageName

        $zipFilePath = Join-Path $pwd "$name.zip"

        Add-Type -assemblyname System.IO.Compression.FileSystem
        Write-Verbose "Zipping ${env:CoreOutput} into $zipFilePath" -verbose
        [System.IO.Compression.ZipFile]::CreateFromDirectory($env:CoreOutput, $zipFilePath)

        $artifacts = New-Object System.Collections.ArrayList
        foreach ($package in $packages) {
            $null = $artifacts.Add($package)
        }

        $null = $artifacts.Add($zipFilePath)

        if ($env:APPVEYOR_REPO_TAG_NAME)
        {
            # ignore the first part of semver, use the preview part
            $preReleaseVersion = ($env:APPVEYOR_REPO_TAG_NAME).Split('-')[1]
        }
        else
        {
            $previewLabel = (git describe --abbrev=0).Split('-')[1].replace('.','')
            if(Test-DailyBuild)
            {
                $previewLabel= "daily-{0}" -f $previewLabel
            }

            $preReleaseVersion = "$previewLabel-$($env:APPVEYOR_BUILD_NUMBER.replace('.','-'))"
        }

        # only publish to nuget feed if it is a daily build and tests passed
        if((Test-DailyBuild) -and $env:TestPassed -eq 'True')
        {
            Publish-NuGetFeed -OutputPath .\nuget-artifacts -VersionSuffix $preReleaseVersion
        }

        $nugetArtifacts = Get-ChildItem .\nuget-artifacts -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }

        if($nugetArtifacts)
        {
            $artifacts.AddRange($nugetArtifacts)
        }

        $pushedAllArtifacts = $true
        $artifacts | ForEach-Object {
            Write-Host "Pushing $_ as Appveyor artifact"
            if(Test-Path $_)
            {
                if($env:Appveyor)
                {
                    Push-AppveyorArtifact $_
                }
            }
            else
            {
                $pushedAllArtifacts = $false
                Write-Warning "Artifact $_ does not exist."
            }

            if($env:NUGET_KEY -and $env:NUGET_URL -and [system.io.path]::GetExtension($_) -ieq '.nupkg')
            {
                log "pushing $_ to $env:NUGET_URL"
                Start-NativeExecution -sb {dotnet nuget push $_ --api-key $env:NUGET_KEY --source "$env:NUGET_URL/api/v2/package"} -IgnoreExitcode
            }            
        }
        if(!$pushedAllArtifacts)
        {
            throw "Some artifacts did not exist!"
        }
    }
    catch {
        Write-Host -Foreground Red $_
    }
}
