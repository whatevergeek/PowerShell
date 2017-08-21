﻿param(
    [Parameter(Mandatory = $true, Position = 0)] $coverallsToken,
    [Parameter(Mandatory = $true, Position = 1)] $codecovToken,
    [Parameter(Position = 2)] $azureLogDrive = "L:\",
    [switch] $SuppressQuiet
)

# Read the XML and create a dictionary for FileUID -> file full path.
function GetFileTable()
{
    $files = $script:covData | Select-Xml './/File'
    foreach($file in $files)
    {
        $script:fileTable[$file.Node.uid] = $file.Node.fullPath
    }
}

# Get sequence points for a particular file
function GetSequencePointsForFile([string] $fileId)
{
    $lineCoverage = [System.Collections.Generic.Dictionary[string,int]]::new()

    $sequencePoints = $script:covData | Select-Xml ".//SequencePoint[@fileid = '$fileId']"

    if($sequencePoints.Count -gt 0)
    {
        foreach($sp in $sequencePoints)
        {
            $visitedCount = [int]::Parse($sp.Node.vc)
            $lineNumber = [int]::Parse($sp.Node.sl)
            $lineCoverage[$lineNumber] += [int]::Parse($visitedCount)
        }

        return $lineCoverage
    }
}

#### Convert the OpenCover XML output for CodeCov.io JSON format as it is smaller.
function ConvertTo-CodeCovJson
{
    param(
        [string] $Path,
        [string] $DestinationPath
    )

    $Script:fileTable = [ordered]@{}
    $Script:covData = [xml] (Get-Content -ReadCount 0 -Raw -Path $Path)
    $totalCoverage = [PSCustomObject]::new()
    $totalCoverage | Add-Member -MemberType NoteProperty -Name "coverage" -Value ([PSCustomObject]::new())

    ## Populate the dictionary with file uid and file names.
    GetFileTable
    $keys = $Script:fileTable.Keys
    $progress=0
    foreach($f in $keys)
    {
        Write-Progress -Id 1 -Activity "Converting to JSON" -Status 'Converting' -PercentComplete ($progress * 100 / $keys.Count) 
        $fileCoverage = GetSequencePointsForFile -fileId $f
        $fileName = $Script:fileTable[$f]
        $previousFileCoverage = $totalCoverage.coverage.${fileName}

        ##Update the values for the lines in the file.
        if($null -ne $previousFileCoverage)
        {
            foreach($lineNumber in $fileCoverage.Keys)
            {
                $previousFileCoverage[$lineNumber] += [int]::Parse($fileCoverage[$lineNumber])
            }
        }
        else ## the file is new, so add the values as a new NoteProperty.
        {
            $totalCoverage.coverage | Add-Member -MemberType NoteProperty -Value $fileCoverage -Name $fileName
        }

        $progress++
    }

    Write-Progress -Id 1 -Completed -Activity "Converting to JSON"

    $totalCoverage | ConvertTo-Json -Depth 5 -Compress | out-file $DestinationPath -Encoding ascii
}

function Write-LogPassThru
{
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position = 0)]
        [string] $Message,
        $Path = "$env:Temp\CodeCoverageRunLogs.txt"
    )

    $message = "{0:d} - {0:t} : {1}" -f ([datetime]::now),$message
    Add-Content -Path $Path -Value $Message -PassThru -Force
}

function Push-CodeCovData
{
    param (
        [Parameter(Mandatory=$true)]$file,
        [Parameter(Mandatory=$true)]$CommitID,
        [Parameter(Mandatory=$false)]$token,
        [Parameter(Mandatory=$false)]$Branch = "master"
    )
    $VERSION="64c1150"
    $url="https://codecov.io"

    $query = "package=bash-${VERSION}&token=${token}&branch=${Branch}&commit=${CommitID}&build=&build_url=&tag=&slug=&yaml=&service=&flags=&pr=&job="
    $uri = "$url/upload/v2?${query}"
    $response = Invoke-WebRequest -Method Post -InFile $file -Uri $uri

    if ( $response.StatusCode -ne 200 )
    {
        Write-LogPassThru -Message "Upload failed for upload uri: $uploaduri"
        throw "upload failed"
    }
}

Write-LogPassThru -Message "***** New Run *****"

Write-LogPassThru -Message "Forcing winrm quickconfig as it is required for remoting tests."
winrm quickconfig -force

$codeCoverageZip = 'https://ci.appveyor.com/api/projects/PowerShell/powershell-f975h/artifacts/CodeCoverage.zip'
$testContentZip = 'https://ci.appveyor.com/api/projects/PowerShell/powershell-f975h/artifacts/tests.zip'
$openCoverZip = 'https://ci.appveyor.com/api/projects/PowerShell/powershell-f975h/artifacts/OpenCover.zip'

Write-LogPassThru -Message "codeCoverageZip: $codeCoverageZip"
Write-LogPassThru -Message "testcontentZip: $testContentZip"
Write-LogPassThru -Message "openCoverZip: $openCoverZip"

$outputBaseFolder = "$env:Temp\CC"
$null = New-Item -ItemType Directory -Path $outputBaseFolder -Force

$openCoverPath = "$outputBaseFolder\OpenCover"
$testRootPath = "$outputBaseFolder\tests"
$testPath = "$testRootPath\powershell"
$psBinPath = "$outputBaseFolder\PSCodeCoverage"
$openCoverTargetDirectory = "$outputBaseFolder\OpenCoverToolset"
$outputLog = "$outputBaseFolder\CodeCoverageOutput.xml"
$elevatedLogs = "$outputBaseFolder\TestResults_Elevated.xml"
$unelevatedLogs = "$outputBaseFolder\TestResults_Unelevated.xml"
$testToolsPath = "$testRootPath\tools"
$jsonFile = "$outputBaseFolder\CC.json"

try
{
    ## This is required so we do not keep on merging coverage reports.
    if(Test-Path $outputLog)
    {
        Remove-Item $outputLog -Force -ErrorAction SilentlyContinue
    }

    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    Write-LogPassThru -Message "Starting downloads."
    Invoke-WebRequest -uri $codeCoverageZip -outfile "$outputBaseFolder\PSCodeCoverage.zip"
    Invoke-WebRequest -uri $testContentZip -outfile "$outputBaseFolder\tests.zip"
    Invoke-WebRequest -uri $openCoverZip -outfile "$outputBaseFolder\OpenCover.zip"
    Write-LogPassThru -Message "Downloads complete. Starting expansion"

    Expand-Archive -path "$outputBaseFolder\PSCodeCoverage.zip" -destinationpath "$psBinPath" -Force
    Expand-Archive -path "$outputBaseFolder\tests.zip" -destinationpath $testRootPath -Force
    Expand-Archive -path "$outputBaseFolder\OpenCover.zip" -destinationpath $openCoverPath -Force

    ## Download Coveralls.net uploader
    $coverallsToolsUrl = 'https://github.com/csMACnz/coveralls.net/releases/download/0.7.0/coveralls.net.0.7.0.nupkg'
    $coverallsPath = "$outputBaseFolder\coveralls"

    ## Saving the nupkg as zip so we can expand it.
    Invoke-WebRequest -uri $coverallsToolsUrl -outfile "$outputBaseFolder\coveralls.zip"
    Expand-Archive -Path "$outputBaseFolder\coveralls.zip" -DestinationPath $coverallsPath -Force

    Write-LogPassThru -Message "Expansion complete."

    Import-Module "$openCoverPath\OpenCover" -Force
    Install-OpenCover -TargetDirectory $openCoverTargetDirectory -force
    Write-LogPassThru -Message "OpenCover installed."

    Write-LogPassThru -Message "TestPath : $testPath"
    Write-LogPassThru -Message "openCoverPath : $openCoverTargetDirectory\OpenCover"
    Write-LogPassThru -Message "psbinpath : $psBinPath"
    Write-LogPassThru -Message "elevatedLog : $elevatedLogs"
    Write-LogPassThru -Message "unelevatedLog : $unelevatedLogs"
    Write-LogPassThru -Message "TestToolsPath : $testToolsPath"

    $openCoverParams = @{outputlog = $outputLog;
        TestPath = $testPath;
        OpenCoverPath = "$openCoverTargetDirectory\OpenCover";
        PowerShellExeDirectory = "$psBinPath";
        PesterLogElevated = $elevatedLogs;
        PesterLogUnelevated = $unelevatedLogs;
        TestToolsModulesPath = "$testToolsPath\Modules";
    }

    if($SuppressQuiet)
    {
        $openCoverParams.Add('SuppressQuiet', $true)
    }

    $openCoverParams | Out-String | Write-LogPassThru
    Write-LogPassThru -Message "Starting test run."

    if(Test-Path $outputLog)
    {
        Remove-Item $outputLog -Force -ErrorAction SilentlyContinue
    }

    Invoke-OpenCover @openCoverParams

    if(Test-Path $outputLog)
    {
        Write-LogPassThru -Message (get-childitem $outputLog).FullName
    }

    Write-LogPassThru -Message "Test run done."

    $gitCommitId = & "$psBinPath\powershell.exe" -noprofile -command { $PSVersiontable.GitCommitId }
    $commitId = $gitCommitId.substring($gitCommitId.LastIndexOf('-g') + 2)

    Write-LogPassThru -Message $commitId

    $coverallsPath = "$outputBaseFolder\coveralls"

    $commitInfo = Invoke-RestMethod -Method Get "https://api.github.com/repos/powershell/powershell/git/commits/$commitId"
    $message = ($commitInfo.message).replace("`n", " ")
    $author = $commitInfo.author.name
    $email = $commitInfo.author.email

    $coverallsExe = Join-Path $coverallsPath "tools\csmacnz.Coveralls.exe"
    $coverallsParams = @("--opencover",
        "-i $outputLog",
        "--repoToken $coverallsToken",
        "--commitId $commitId",
        "--commitBranch master",
        "--commitAuthor `"$author`"",
        "--commitEmail $email",
        "--commitMessage `"$message`""
    )

    $coverallsParams | ForEach-Object { Write-LogPassThru -Message $_ }

    Write-LogPassThru -Message "Uploading to CoverAlls"
    & $coverallsExe """$coverallsParams"""

    Write-LogPassThru -Message "Uploading to CodeCov"
    ConvertTo-CodeCovJson -Path $outputLog -DestinationPath $jsonFile
    Push-CodeCovData -file $jsonFile -CommitID $commitId -token $codecovToken -Branch 'master'

    Write-LogPassThru -Message "Upload complete."
}
catch
{
    Write-LogPassThru -Message $_
}
finally
{
    ## See if Azure log directory is mounted
    if(Test-Path $azureLogDrive)
    {
        ##Create yyyy-dd folder
        $monthFolder = "{0:yyyy-MM}" -f [datetime]::Now
        $monthFolderFullPath = New-Item -Path (Join-Path $azureLogDrive $monthFolder) -ItemType Directory -Force
        $windowsFolderPath = New-Item (Join-Path $monthFolderFullPath "Windows") -ItemType Directory -Force

        $destinationPath = Join-Path $env:Temp ("CodeCoverageLogs-{0:yyyy_MM_dd}-{0:hh_mm_ss}.zip" -f [datetime]::Now)
        Compress-Archive -Path $elevatedLogs,$unelevatedLogs,$outputLog -DestinationPath $destinationPath
        Copy-Item $destinationPath $windowsFolderPath -Force -ErrorAction SilentlyContinue

        Remove-Item -Path $destinationPath -Force -ErrorAction SilentlyContinue
    }

    ## Disable the cleanup till we stabilize.
    #Remove-Item -recurse -force -path $outputBaseFolder
    $ErrorActionPreference = $oldErrorActionPreference
}
