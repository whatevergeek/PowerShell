Describe "Get-Content" -Tags "CI" {
    $testString = "This is a test content for a file"
    $nl         = [Environment]::NewLine
    $firstline  = "Here's a first line "
    $secondline = " here's a second line"
    $thirdline  = "more text"
    $fourthline = "just to make sure"
    $fifthline  = "there's plenty to work with"
    $testString2 = $firstline + $nl + $secondline + $nl + $thirdline + $nl + $fourthline + $nl + $fifthline
    $testPath   = Join-Path -Path $TestDrive -ChildPath testfile1
    $testPath2  = Join-Path -Path $TestDrive -ChildPath testfile2

    BeforeEach {
        New-Item -Path $testPath -ItemType file -Force -Value $testString
        New-Item -Path $testPath2 -ItemType file -Force -Value $testString2
    }
    AfterEach {
        Remove-Item -Path $testPath -Force
        Remove-Item -Path $testPath2 -Force
    }
    It "Should throw an error on a directory  " {
        try {
            Get-Content . -ErrorAction Stop
            throw "No Exception!"
        }
        catch {
            $_.FullyQualifiedErrorId | should be "GetContentReaderUnauthorizedAccessError,Microsoft.PowerShell.Commands.GetContentCommand"
        }
    }
    It "Should return an Object when listing only a single line and the correct information from a file" {
        $content = (Get-Content -Path $testPath)
        $content | Should Be $testString
        $content.Count | Should Be 1
        $content | Should BeOfType "System.String"
    }
    It "Should deliver an array object when listing a file with multiple lines and the correct information from a file" {
        $content = (Get-Content -Path $testPath2)
        @(Compare-Object $content $testString2.Split($nl) -SyncWindow 0).Length | Should Be 0
        ,$content | Should BeOfType "System.Array"
    }
    It "Should be able to return a specific line from a file" {
        (Get-Content -Path $testPath2)[1] | Should be $secondline
    }
    It "Should be able to specify the number of lines to get the content of using the TotalCount switch" {
        $returnArray    = (Get-Content -Path $testPath2 -TotalCount 2)
        $returnArray[0] | Should Be $firstline
        $returnArray[1] | Should Be $secondline
    }
    It "Should be able to specify the number of lines to get the content of using the Head switch" {
        $returnArray    = (Get-Content -Path $testPath2 -Head 2)
        $returnArray[0] | Should Be $firstline
        $returnArray[1] | Should Be $secondline
    }
    It "Should be able to specify the number of lines to get the content of using the First switch" {
        $returnArray    = (Get-Content -Path $testPath2 -First 2)
        $returnArray[0] | Should Be $firstline
        $returnArray[1] | Should Be $secondline
    }
    It "Should return the last line of a file using the Tail switch" {
        Get-Content -Path $testPath -Tail 1 | Should Be $testString
    }
    It "Should return the last lines of a file using the Last alias" {
        Get-Content -Path $testPath2 -Last 1 | Should Be $fifthline
    }
    It "Should be able to get content within a different drive" {
        Push-Location env:
        $expectedoutput = [Environment]::GetEnvironmentVariable("PATH");
        { Get-Content PATH } | Should Not Throw
        Get-Content PATH     | Should Be $expectedoutput
        Pop-Location
    }
    #[BugId(BugDatabase.WindowsOutOfBandReleases, 906022)]
    It "should throw 'PSNotSupportedException' when you set-content to an unsupported provider" -Skip:($IsLinux -Or $IsMacOS) {
        {get-content -path HKLM:\\software\\microsoft -ea stop} | Should Throw "IContentCmdletProvider interface is not implemented"
    }
    It "should Get-Content with a variety of -Tail and -ReadCount values" {#[DRT]
        set-content -path $testPath "Hello,World","Hello2,World2","Hello3,World3","Hello4,World4"
        $result=get-content -path $testPath -readcount:-1 -tail 5
        $result.Length | Should Be 4
        $expected = "Hello,World","Hello2,World2","Hello3,World3","Hello4,World4"
        for ($i = 0; $i -lt $result.Length ; $i++) { $result[$i]  | Should BeExactly $expected[$i]}
        $result=get-content -path $testPath -readcount 0 -tail 3
        $result.Length    | Should Be 3
        $expected = "Hello2,World2","Hello3,World3","Hello4,World4"
        for ($i = 0; $i -lt $result.Length ; $i++) { $result[$i]  | Should BeExactly $expected[$i]}
        $result=get-content -path $testPath -readcount 1 -tail 3
        $result.Length    | Should Be 3
        $expected = "Hello2,World2","Hello3,World3","Hello4,World4"
        for ($i = 0; $i -lt $result.Length ; $i++) { $result[$i]  | Should BeExactly $expected[$i]}
        $result=get-content -path $testPath -readcount 99999 -tail 3
        $result.Length    | Should Be 3
        $expected = "Hello2,World2","Hello3,World3","Hello4,World4"
        for ($i = 0; $i -lt $result.Length ; $i++) { $result[$i]  | Should BeExactly $expected[$i]}
        $result=get-content -path $testPath -readcount 2 -tail 3
        $result.Length    | Should Be 2
        $expected = "Hello2,World2","Hello3,World3"
        $expected = $expected,"Hello4,World4"
        for ($i = 0; $i -lt $result.Length ; $i++) { $result[$i]  | Should BeExactly $expected[$i]}
        $result=get-content -path $testPath -readcount 2 -tail 2
        $result.Length    | Should Be 2
        $expected = "Hello3,World3","Hello4,World4"
        for ($i = 0; $i -lt $result.Length ; $i++) { $result[$i]  | Should BeExactly $expected[$i]}
        $result=get-content -path $testPath -delimiter "," -tail 2
        $result.Length    | Should Be 2
        $expected = "World3${nl}Hello4", "World4${nl}"
        for ($i = 0; $i -lt $result.Length ; $i++) { $result[$i]  | Should BeExactly $expected[$i]}
        $result=get-content -path $testPath -delimiter "o" -tail 3
        $result.Length    | Should Be 3
        $expected = "rld3${nl}Hell", '4,W', "rld4${nl}"
        for ($i = 0; $i -lt $result.Length ; $i++) { $result[$i]  | Should BeExactly $expected[$i]}
        $result=get-content -path $testPath -encoding:Byte -tail 10
        $result.Length    | Should Be 10
        if ($IsWindows) {
            $expected =      52, 44, 87, 111, 114, 108, 100, 52, 13, 10
        } else {
            $expected = 111, 52, 44, 87, 111, 114, 108, 100, 52, 10
        }
        for ($i = 0; $i -lt $result.Length ; $i++) { $result[$i]  | Should BeExactly $expected[$i]}
    }
    #[BugId(BugDatabase.WindowsOutOfBandReleases, 905829)]
    It "should get-content that matches the input string"{
        set-content $testPath "Hello,llllWorlld","Hello2,llllWorlld2"
        $result=get-content $testPath -delimiter "ll"
        $result.Length    | Should Be 9
        $expected = 'He', 'o,', '', 'Wor', "d${nl}He", 'o2,', '', 'Wor', "d2${nl}"
        for ($i = 0; $i -lt $result.Length ; $i++) { $result[$i]    | Should BeExactly $expected[$i]}
    }

    It "Should support NTFS streams using colon syntax" -Skip:(!$IsWindows) {
        Set-Content "${testPath}:Stream" -Value "Foo"
        { Test-Path "${testPath}:Stream" | ShouldBeErrorId "ItemExistsNotSupportedError,Microsoft.PowerShell.Commands,TestPathCommand" }
        Get-Content "${testPath}:Stream" | Should BeExactly "Foo"
        Get-Content $testPath | Should BeExactly $testString
    }

    It "Should support NTFS streams using -stream" -Skip:(!$IsWindows) {
        Set-Content -Path $testPath -Stream hello -Value World
        Get-Content -Path $testPath | Should Be $testString
        Get-Content -Path $testPath -Stream hello | Should Be "World"
        $item = Get-Item -Path $testPath -Stream hello
        $item | Should BeOfType System.Management.Automation.Internal.AlternateStreamData
        $item.Stream | Should Be "hello"
        Clear-Content -Path $testPath -Stream hello
        Get-Content -Path $testPath -Stream hello | Should BeNullOrEmpty
        Remove-Item -Path $testPath -Stream hello
        { Get-Content -Path $testPath -Stream hello | ShouldBeErrorId "GetContentReaderFileNotFoundError,Microsoft.PowerShell.Commands.GetContentCommand" }
    }

    It "Should support colons in filename on Linux/Mac" -Skip:($IsWindows) {
        Set-Content "${testPath}:Stream" -Value "Hello"
        "${testPath}:Stream" | Should Exist
        Get-Content "${testPath}:Stream" | Should BeExactly "Hello"
    }

    It "-Stream is not a valid parameter for <cmdlet> on Linux/Mac" -Skip:($IsWindows) -TestCases @(
        @{cmdlet="get-content"},
        @{cmdlet="set-content"},
        @{cmdlet="clear-content"},
        @{cmdlet="add-content"},
        @{cmdlet="get-item"},
        @{cmdlet="remove-item"}
        ) {
        param($cmdlet)
        (Get-Command $cmdlet).Parameters["stream"] | Should BeNullOrEmpty
    }
}
