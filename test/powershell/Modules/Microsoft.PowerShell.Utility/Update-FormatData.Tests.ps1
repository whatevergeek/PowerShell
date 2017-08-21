Describe "Update-FormatData" -Tags "CI" {

    BeforeAll {
        $path = Join-Path -Path $TestDrive -ChildPath "outputfile.ps1xml"
        $ps = [powershell]::Create()
        $iss = [system.management.automation.runspaces.initialsessionstate]::CreateDefault2()
        $rs = [system.management.automation.runspaces.runspacefactory]::CreateRunspace($iss)
        $rs.Open()
        $ps.Runspace = $rs
    }
    AfterAll {
        $rs.Close()
        $ps.Dispose()
    }
    Context "Validate Update-FormatData update correctly" {

        It "Should not throw upon reloading previous formatting file" {
            { Update-FormatData } | Should Not throw
        }

        It "Should validly load formatting data" {
            Get-FormatData -typename System.Diagnostics.Process | Export-FormatData -Path $path
            $null = $ps.AddScript("Update-FormatData -prependPath $path")
            $ps.Invoke()
            $ps.HadErrors | Should be $false
        }
    }
}

Describe "Update-FormatData basic functionality" -Tags "CI" {
    BeforeAll {
        $testfilename = "testfile.ps1xml"
        $testfile = Join-Path -Path $TestDrive -ChildPath $testfilename

        $xmlContent=@"
                <Types>
                    <Type>
                        <Name>AnyName</Name>
                        <Members>
                            <PropertySet>
                                <Name>PropertySetName</Name>
                                <ReferencedProperties>
                                    <Name>FirstName</Name>
                                    <Name>LastName</Name>
                                </ReferencedProperties>
                            </PropertySet>
                        </Members>
                    </Type>
                </Types>
"@
        $xmlContent > $testfile
    }

    It "Update-FormatData with WhatIf should work"{

        { Update-FormatData -Append $testfile -WhatIf } | Should Not Throw
        { Update-FormatData -Prepend $testfile -WhatIf } | Should Not Throw
    }
}


Describe "Update-FormatData with resources in CustomControls" -Tags "CI" {

    BeforeAll {
        $templatePath = Join-Path $PSScriptRoot (Join-Path 'assets' 'UpdateFormatDataTests.format.ps1xml')
        $formatFilePath = Join-Path $TestDrive 'UpdateFormatDataTests.format.ps1xml'
        $ps = [powershell]::Create()
        $iss = [system.management.automation.runspaces.initialsessionstate]::CreateDefault2()
        $rs = [system.management.automation.runspaces.runspacefactory]::CreateRunspace($iss)
        $rs.Open()
        $ps.Runspace = $rs
    }
    AfterAll {
        $rs.Close()
        $ps.Dispose()
    }
    Context "Validate Update-FormatData" {
        It "Resources in WindowsPS syntax should be loaded successfully" {
            $format = Get-Content -Path $templatePath -Raw
            $format.Replace("%BaseName%","FileSystemProviderStrings") | Set-Content -Path $formatFilePath -Force
            $null = $ps.AddScript("Update-FormatData -PrependPath $formatFilePath")
            $ps.Streams.Error.Clear()
            $ps.Invoke()
            $ps.Streams.Error | Should BeNullOrEmpty

        }
        It "Resources in CorePS syntax should be loaded successfully" {
            $format = Get-Content -Path $templatePath -Raw
            $format.Replace("%BaseName%","System.Management.Automation.resources.FileSystemProviderStrings") | Set-Content -Path $formatFilePath -Force
            $null = $ps.AddScript("Update-FormatData -PrependPath $formatFilePath")
            $ps.Streams.Error.Clear()
            $ps.Invoke()
            $ps.Streams.Error | Should BeNullOrEmpty
        }
        It "Verify assembly path in error message when resource is Not found" {
            $format = Get-Content -Path $templatePath -Raw
            $format.Replace("%BaseName%","NonExistingResource") | Set-Content -Path $formatFilePath -Force
            $null = $ps.AddScript("Update-FormatData -PrependPath $formatFilePath")
            $ps.Streams.Error.Clear()
            $ps.Invoke()
            $sma = [appdomain]::CurrentDomain.GetAssemblies() | ? { if ($_.Location) {$_.Location.EndsWith("System.Management.Automation.dll")}}
            $smaLocation = $sma.Location
            $ps.Streams.Error | %{ $_.Exception.Message.Contains($smaLocation) | Should be $true }
            $ps.Streams.Error | %{ $_.FullyQualifiedErrorId | Should Match 'FormatXmlUpdateException' }
        }
    }
}
