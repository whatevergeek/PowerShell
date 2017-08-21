param(
    [switch]$Bootstrap
)
Import-Module $PSScriptRoot/../build.psm1 -Force
Import-Module $PSScriptRoot/packaging -Force

# This function retrieves the appropriate svg to be used when presenting
# the daily test run badge
# the location in azure is public readonly
function Get-DailyBadge
{
    param (
        [Parameter(Mandatory=$true,Position=0)][ValidateSet("Pass","Fail")]$result
        )
    $PASS = "https://jimtru1979.blob.core.windows.net/badges/DailyBuild.Pass.svg"
    $FAIL = "https://jimtru1979.blob.core.windows.net/badges/DailyBuild.Fail.svg"

    if ( $result -eq "Pass" ) { $BadgeUrl = $PASS } else { $BadgeUrl = $FAIL }
    $response = Invoke-WebRequest -Uri $BadgeUrl
    if ( $response.StatusCode -ne 200 ) { throw "Could not read badge '$BadgeUrl'" }
    $response.Content
}

# This function uses Azure REST api to update the daily test pass results
# it relies on writing a specific SVG into a constant location so the
# README.MD can report on the status of the daily test pass
# it also relies on two environment variables which need to be set in the
# Travis-CI config which is the account name and key for the azure blob location
#
# the best way to do this would be if travis-ci supported a webcall to get
# the status of cron_job builds, but it doesn't, so we have this
function Set-DailyBuildBadge
{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param ( [Parameter(Mandatory=$true,Position=0)]$content )
    $method = "PUT"
    $headerDate = '2015-12-11'

    $storageAccountName = $Env:TestResultAccountName
    $storageAccountKey = $Env:TestResultAccountKey

    # this is the url referenced in README.MD which displays the badge
    $Url = "https://jimtru1979.blob.core.windows.net/badges/DailyBuildStatus.svg"

    $body = $content
    $bytes = ([System.Text.Encoding]::UTF8.GetBytes($body))
    $contentLength = $bytes.length

    $now = [datetime]::UtcNow.ToString("R", [System.Globalization.CultureInfo]::InvariantCulture)
    $headers = @{
        "x-ms-date"      = $now
        "cache-control"  = "no-cache"
        "x-ms-blob-type" = "BlockBlob"
        "x-ms-version"   = "$headerDate"
    }

    $contentType = "image/svg+xml"
    # more info: https://docs.microsoft.com/en-us/rest/api/storageservices/fileservices/put-blob
    $sb = [text.stringbuilder]::new()
    # can't use AppendLine because the `r`n causes the command to fail, it must be `n and only `n
    $null = $sb.Append("$method`n")
    $null = $sb.Append("`n")
    $null = $sb.Append("`n")
    $null = $sb.Append("$contentLength`n")
    $null = $sb.Append("`n")
    $null = $sb.Append("$contentType`n")
    $null = $sb.Append("`n")
    $null = $sb.Append("`n")
    $null = $sb.Append("`n")
    $null = $sb.Append("`n")
    $null = $sb.Append("`n")
    $null = $sb.Append("`n")

    $null = $sb.Append("x-ms-blob-type:" + $headers["x-ms-blob-type"] + "`n")
    $null = $sb.Append("x-ms-date:" + $headers["x-ms-date"] + "`n")
    $null = $sb.Append("x-ms-version:" + $headers["x-ms-version"] + "`n")
    $null = $sb.Append("/" + $storageAccountName + ([System.Uri]::new($url).AbsolutePath))

    $dataToMac = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
    $accountKeyBytes = [System.Convert]::FromBase64String($storageAccountKey)
    $hmac = [System.Security.Cryptography.HMACSHA256]::new($accountKeyBytes)
    $signature = [System.Convert]::ToBase64String($hmac.ComputeHash($dataToMac))

    $headers["Authorization"]  = "SharedKey " + $storageAccountName + ":" + $signature

    if ( $PSCmdlet.ShouldProcess("$signaturestring")) 
    {
        # if this fails, it will throw, you can't check the response for a success code
        $response = Invoke-RestMethod -Uri $Url -Method $method -headers $headers -Body $body -ContentType "image/svg+xml"
    }
}


# https://docs.travis-ci.com/user/environment-variables/
# TRAVIS_EVENT_TYPE: Indicates how the build was triggered.
# One of push, pull_request, api, cron.
$isPR = $env:TRAVIS_EVENT_TYPE -eq 'pull_request'

# For PRs, Travis-ci strips out [ and ] so read the message directly from git
if($env:TRAVIS_EVENT_TYPE -eq 'pull_request')
{
    # Get the second log entry body
    # The first log is a merge for a PR
    $commitMessage = git log --format=%B -n 1 --skip=1
}
else
{
    $commitMessage = $env:TRAVIS_COMMIT_MESSAGE
}


# Run a full build if the build was trigger via cron, api or the commit message contains `[Feature]`
$hasFeatureTag = $commitMessage -match '\[feature\]'
$isDailyBuild = $env:TRAVIS_EVENT_TYPE -eq 'cron' -or $env:TRAVIS_EVENT_TYPE -eq 'api'
$isFullBuild = $isDailyBuild -or $hasFeatureTag

if($Bootstrap.IsPresent)
{
    Write-Host -Foreground Green "Executing travis.ps1 -BootStrap `$isPR='$isPr' - $commitMessage"
    # Make sure we have all the tags
    Sync-PSTags -AddRemoteIfMissing
    Start-PSBootstrap -Package:(-not $isPr)
}
else 
{
    $BaseVersion = (Get-PSVersion -OmitCommitId) + '-'
    Write-Host -Foreground Green "Executing travis.ps1 `$isPR='$isPr' `$isFullBuild='$isFullBuild' - $commitMessage"
    $output = Split-Path -Parent (Get-PSOutput -Options (New-PSOptions))

    # CrossGen'ed assemblies cause a hang to happen intermittently when running powershell class
    # basic parsing tests in Linux/OSX. The hang seems to happen when generating dynamic assemblies.
    # This issue has been reported to CoreCLR team. We need to work around it for now because
    # the Travis CI build failures caused by this is draining our builder resource and severely
    # affect our daily work. The workaround is:
    #  1. For pull request and push commit, build without '-CrossGen' and run the parsing tests
    #  2. For nightly build, build with '-CrossGen' but don't run the parsing tests
    # With this workaround, CI builds triggered by pull request and push commit will exercise
    # the parsing tests with IL assemblies, while nightly builds will exercise CrossGen'ed assemblies
    # without running those class parsing tests so as to avoid the hang.
    # NOTE: this change should be reverted once the 'CrossGen' issue is fixed by CoreCLR. The issue
    #       is tracked by https://github.com/dotnet/coreclr/issues/9745
    $originalProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue' 
    try {
        ## We use CrossGen build to run tests only if it's the daily build.
        Start-PSBuild -CrossGen:$isDailyBuild -PSModuleRestore
    }
    finally{
        $ProgressPreference = $originalProgressPreference    
    }

    $pesterParam = @{ 'binDir' = $output }

    if ($isFullBuild) {
        $pesterParam['Tag'] = @('CI','Feature','Scenario')
        $pesterParam['ExcludeTag'] = @()
    } else {
        $pesterParam['Tag'] = @('CI')
        $pesterParam['ThrowOnFailure'] = $true
    }

    # Remove telemetry semaphore file in CI
    $telemetrySemaphoreFilepath = Join-Path $output DELETE_ME_TO_DISABLE_CONSOLEHOST_TELEMETRY
    if ( Test-Path "${telemetrySemaphoreFilepath}" ) {
        Remove-Item -force ${telemetrySemaphoreFilepath}
    }

    Start-PSPester @pesterParam

    if (-not $isPr) {
        # Run 'CrossGen' for push commit, so that we can generate package.
        # It won't rebuild powershell, but only CrossGen the already built assemblies.
        if (-not $isDailyBuild) { Start-PSBuild -CrossGen }
        
        $packageParams = @{}
        if($env:TRAVIS_BUILD_NUMBER)
        {
            $version = $BaseVersion + $env:TRAVIS_BUILD_NUMBER
            $packageParams += @{Version=$version}
        }
        # Only build packages for branches, not pull requests
        $packages = @(Start-PSPackage @packageParams -SkipReleaseChecks)
        # Packaging AppImage depends on the deb package
        $packages += Start-PSPackage  @packageParams -Type AppImage -SkipReleaseChecks
        foreach($package in $packages)
        {
            # Publish the packages to the nuget feed if:
            # 1 - It's a Daily build (already checked, for not a PR)
            # 2 - We have the info to publish (NUGET_KEY and NUGET_URL)
            # 3 - it's a nupkg file
            if($isDailyBuild -and $env:NUGET_KEY -and $env:NUGET_URL -and [system.io.path]::GetExtension($package) -ieq '.nupkg')
            {
                log "pushing $package to $env:NUGET_URL"
                Start-NativeExecution -sb {dotnet nuget push $package --api-key $env:NUGET_KEY --source "$env:NUGET_URL/api/v2/package"} -IgnoreExitcode
            }            
        }

        try {
            # this throws if there was an error
            Test-PSPesterResults
            $result = "PASS"
        }
        catch {
            $resultError = $_
            $result = "FAIL"
        }
        if ( $isDailyBuild ) {
            # now update the badge if you've done a full build, these are not fatal issues
            try {
                $svgData = Get-DailyBadge -result $result
                if ( ! $svgData ) {
                    write-warning "Could not retrieve $result badge"
                }
                else {
                    Write-Verbose -verbose "Setting status badge to '$result'"
                    Set-DailyBuildBadge -content $svgData
                }
            }
            catch {
                Write-Warning "Could not update status badge: $_"
            }
        }
        # if the tests did not pass, throw the reason why
        if ( $result -eq "FAIL" ) {
            Throw $resultError
        }
    }

    Start-PSxUnit
}
