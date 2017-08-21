using namespace System.Diagnostics

# Minishell (Singleshell) is a powershell concept.
# Its primary use-case is when somebody executes a scriptblock in the new powershell process.
# The objects are automatically marshelled to the child process and
# back to the parent session, so users can avoid custom
# serialization to pass objects between two processes.

Describe 'minishell for native executables' -Tag 'CI' {

    BeforeAll {
        $powershell = Join-Path -Path $PsHome -ChildPath "powershell"
    }

    Context 'Streams from minishell' {

        It 'gets a hashtable object from minishell' {
            $output = & $powershell -noprofile { @{'a' = 'b'} }
            ($output | Measure-Object).Count | Should Be 1
            $output | Should BeOfType 'Hashtable'
            $output['a'] | Should Be 'b'
        }

        It 'gets the error stream from minishell' {
            $output = & $powershell -noprofile { Write-Error 'foo' } 2>&1
            ($output | Measure-Object).Count | Should Be 1
            $output | Should BeOfType 'System.Management.Automation.ErrorRecord'
            $output.FullyQualifiedErrorId | Should Be 'Microsoft.PowerShell.Commands.WriteErrorException'
        }

        It 'gets the information stream from minishell' {
            $output = & $powershell -noprofile { Write-Information 'foo' } 6>&1
            ($output | Measure-Object).Count | Should Be 1
            $output | Should BeOfType 'System.Management.Automation.InformationRecord'
            $output | Should Be 'foo'
        }
    }

    Context 'Streams to minishell' {
        It "passes input into minishell" {
            $a = 1,2,3
            $val  = $a | & $powershell -noprofile -command { $input }
            $val.Count | Should Be 3
            $val[0] | Should Be 1
            $val[1] | Should Be 2
            $val[2] | Should Be 3
        }
    }
}

Describe "ConsoleHost unit tests" -tags "Feature" {

    BeforeAll {
        $powershell = Join-Path -Path $PsHome -ChildPath "powershell"
        $ExitCodeBadCommandLineParameter = 64

        function NewProcessStartInfo([string]$CommandLine, [switch]$RedirectStdIn)
        {
            return [ProcessStartInfo]@{
                FileName               = $powershell
                Arguments              = $CommandLine
                RedirectStandardInput  = $RedirectStdIn
                RedirectStandardOutput = $true
                RedirectStandardError  = $true
                UseShellExecute        = $false
            }
        }

        function RunPowerShell([ProcessStartInfo]$si)
        {
            $process = [Process]::Start($si)

            return $process
        }

        function EnsureChildHasExited([Process]$process, [int]$WaitTimeInMS = 15000)
        {
            $process.WaitForExit($WaitTimeInMS)

            if (!$process.HasExited)
            {
                $process.HasExited | Should Be $true
                $process.Kill()
            }
        }
    }

    AfterEach {
        $Error.Clear()
    }

    Context "ShellInterop" {
        It "Verify Parsing Error Output Format Single Shell should throw exception" {
            try
            {
                & $powershell -outp blah -comm { $input }
                Throw "Test execution should not reach here!"
            }
            catch
            {
                $_.FullyQualifiedErrorId | Should Be "IncorrectValueForFormatParameter"
            }
        }

        It "Verify Validate Dollar Error Populated should throw exception" {
            $origEA = $ErrorActionPreference
            $ErrorActionPreference = "Stop"
            try
            {
                $a = 1,2,3
                $a | & $powershell -noprofile -command { wgwg-wrwrhqwrhrh35h3h3}
                Throw "Test execution should not reach here!"
            }
            catch
            {
                $_.ToString() | Should Match "wgwg-wrwrhqwrhrh35h3h3"
                $_.FullyQualifiedErrorId | Should Be "CommandNotFoundException"
            }
            finally
            {
                $ErrorActionPreference = $origEA
            }
        }

        It "Verify Validate Output Format As Text Explicitly Child Single Shell should works" {
            {
                $a="blahblah"
                $a | & $powershell -noprofile -out text -com { $input }
            } | Should Not Throw
        }

        It "Verify Parsing Error Input Format Single Shell should throw exception" {
            try
            {
                & $powershell -input blah -comm { $input }
                Throw "Test execution should not reach here!"
            }
            catch
            {
                $_.FullyQualifiedErrorId | Should Be "IncorrectValueForFormatParameter"
            }
        }
    }
    Context "CommandLine" {
        It "simple -args" {
            & $powershell -noprofile { $args[0] } -args "hello world" | Should Be "hello world"
        }

        It "array -args" {
            & $powershell -noprofile { $args[0] } -args 1,(2,3) | Should Be 1
            (& $powershell -noprofile { $args[1] } -args 1,(2,3))[1]  | Should Be 3
        }
        foreach ($x in "--help", "-help", "-h", "-?", "--he", "-hel", "--HELP", "-hEl") {
            It "Accepts '$x' as a parameter for help" {
                & $powershell -noprofile $x | Where-Object { $_ -match "PowerShell[.exe] -Help | -? | /?" } | Should Not BeNullOrEmpty
            }
        }

        It "Should accept a Base64 encoded command" {
            $commandString = "Get-Location"
            $encodedCommand = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($commandString))
            # We don't compare to `Get-Location` directly because object and formatted output comparisons are difficult
            $expected = & $powershell -noprofile -command $commandString
            $actual = & $powershell -noprofile -EncodedCommand $encodedCommand
            $actual | Should Be $expected
        }

        It "-Version should return the engine version" {
            $currentVersion = "powershell " + $PSVersionTable.GitCommitId.ToString()
            $observed = & $powershell -version
            $observed | should be $currentVersion
        }

        It "-Version should ignore other parameters" {
            $currentVersion = "powershell " + $PSVersionTable.GitCommitId.ToString()
            $observed = & $powershell -version -command get-date
            # no extraneous output
            $observed | should be $currentVersion
        }

        It "-File should be default parameter" {
            Set-Content -Path $testdrive/test -Value "'hello'"
            $observed = & $powershell -NoProfile $testdrive/test
            $observed | Should Be "hello"
        }

        It "-File accepts scripts with and without .ps1 extension: <Filename>" -TestCases @(
            @{Filename="test.ps1"},
            @{Filename="test"}
        ) {
            param($Filename)
            Set-Content -Path $testdrive/$Filename -Value "'hello'"
            $observed = & $powershell -NoProfile -File $testdrive/$Filename
            $observed | Should Be "hello"
        }

        It "-File should pass additional arguments to script" {
            Set-Content -Path $testdrive/script.ps1 -Value 'foreach($arg in $args){$arg}'
            $observed = & $powershell -NoProfile $testdrive/script.ps1 foo bar
            $observed.Count | Should Be 2
            $observed[0] | Should Be "foo"
            $observed[1] | Should Be "bar"
        }

        It "-File should be able to pass bool string values as string to parameters: <BoolString>" -TestCases @(
            # validates case is preserved
            @{BoolString = '$truE'},
            @{BoolString = '$falSe'},
            @{BoolString = 'trUe'},
            @{BoolString = 'faLse'}
        ) {
            param([string]$BoolString)
            Set-Content -Path $testdrive/test.ps1 -Value 'param([string]$bool) $bool'
            $observed = & $powershell -NoProfile -Nologo -File $testdrive/test.ps1 -Bool $BoolString
            $observed | Should Be $BoolString
        }

        It "-File should be able to pass bool string values as string to positional parameters: <BoolString>" -TestCases @(
            # validates case is preserved
            @{BoolString = '$tRue'},
            @{BoolString = '$falSe'},
            @{BoolString = 'tRUe'},
            @{BoolString = 'fALse'}
        ) {
            param([string]$BoolString)
            Set-Content -Path $testdrive/test.ps1 -Value 'param([string]$bool) $bool'
            $observed = & $powershell -NoProfile -Nologo -File $testdrive/test.ps1 $BoolString
            $observed | Should BeExactly $BoolString
        }

        It "-File should be able to pass bool string values as bool to switches: <BoolString>" -TestCases @(
            @{BoolString = '$tRue'; BoolValue = 'True'},
            @{BoolString = '$faLse'; BoolValue = 'False'},
            @{BoolString = 'tRue'; BoolValue = 'True'},
            @{BoolString = 'fAlse'; BoolValue = 'False'}
        ) {
            param([string]$BoolString, [string]$BoolValue)
            Set-Content -Path $testdrive/test.ps1 -Value 'param([switch]$switch) $switch.IsPresent'
            $observed = & $powershell -NoProfile -Nologo -File $testdrive/test.ps1 -switch:$BoolString
            $observed | Should Be $BoolValue
        }

        It "-File should return exit code from script"  -TestCases @(
            @{Filename = "test.ps1"},
            @{Filename = "test"}
        ) {
            param($Filename)
            Set-Content -Path $testdrive/$Filename -Value 'exit 123'
            & $powershell $testdrive/$Filename
            $LASTEXITCODE | Should Be 123
        }
    }

    Context "Pipe to/from powershell" {
        $p = [PSCustomObject]@{X=10;Y=20}

        It "xml input" {
            $p | & $powershell -noprofile { $input | Foreach-Object {$a = 0} { $a += $_.X + $_.Y } { $a } } | Should Be 30
            $p | & $powershell -noprofile -inputFormat xml { $input | Foreach-Object {$a = 0} { $a += $_.X + $_.Y } { $a } } | Should Be 30
        }

        It "text input" {
            # Join (multiple lines) and remove whitespace (we don't care about spacing) to verify we converted to string (by generating a table)
            $p | & $powershell -noprofile -inputFormat text { -join ($input -replace "\s","") } | Should Be "XY--1020"
        }

        It "xml output" {
            & $powershell -noprofile { [PSCustomObject]@{X=10;Y=20} } | Foreach-Object {$a = 0} { $a += $_.X + $_.Y } { $a } | Should Be 30
            & $powershell -noprofile -outputFormat xml { [PSCustomObject]@{X=10;Y=20} } | Foreach-Object {$a = 0} { $a += $_.X + $_.Y } { $a } | Should Be 30
        }

        It "text output" {
            # Join (multiple lines) and remove whitespace (we don't care about spacing) to verify we converted to string (by generating a table)
            -join (& $powershell -noprofile -outputFormat text { [PSCustomObject]@{X=10;Y=20} }) -replace "\s","" | Should Be "XY--1020"
        }
    }

    Context "Redirected standard output" {
        It "Simple redirected output" {
            $si = NewProcessStartInfo "-noprofile -c 1+1"
            $process = RunPowerShell $si
            $process.StandardOutput.ReadToEnd() | Should Be 2
            EnsureChildHasExited $process
        }
    }

    Context "Input redirected but not reading from stdin (not really interactive)" {
        # Tests under this context are testing that we do not read from StandardInput
        # even though it is redirected - we want to make sure we don't hang.
        # So none of these tests should close StandardInput

        It "Redirected input w/ implicit -Command w/ -NonInteractive" {
            $si = NewProcessStartInfo "-NonInteractive -noprofile -c 1+1" -RedirectStdIn
            $process = RunPowerShell $si
            $process.StandardOutput.ReadToEnd() | Should Be 2
            EnsureChildHasExited $process
        }

        It "Redirected input w/ implicit -Command w/o -NonInteractive" {
            $si = NewProcessStartInfo "-noprofile -c 1+1" -RedirectStdIn
            $process = RunPowerShell $si
            $process.StandardOutput.ReadToEnd() | Should Be 2
            EnsureChildHasExited $process
        }

        It "Redirected input w/ explicit -Command w/ -NonInteractive" {
            $si = NewProcessStartInfo "-NonInteractive -noprofile -Command 1+1" -RedirectStdIn
            $process = RunPowerShell $si
            $process.StandardOutput.ReadToEnd() | Should Be 2
            EnsureChildHasExited $process
        }

        It "Redirected input w/ explicit -Command w/o -NonInteractive" {
            $si = NewProcessStartInfo "-noprofile -Command 1+1" -RedirectStdIn
            $process = RunPowerShell $si
            $process.StandardOutput.ReadToEnd() | Should Be 2
            EnsureChildHasExited $process
        }

        It "Redirected input w/ -File w/ -NonInteractive" {
            '1+1' | Out-File -Encoding Ascii -FilePath TestDrive:test.ps1 -Force
            $si = NewProcessStartInfo "-noprofile -NonInteractive -File $testDrive\test.ps1" -RedirectStdIn
            $process = RunPowerShell $si
            $process.StandardOutput.ReadToEnd() | Should Be 2
            EnsureChildHasExited $process
        }

        It "Redirected input w/ -File w/o -NonInteractive" {
            '1+1' | Out-File -Encoding Ascii -FilePath TestDrive:test.ps1 -Force
            $si = NewProcessStartInfo "-noprofile -File $testDrive\test.ps1" -RedirectStdIn
            $process = RunPowerShell $si
            $process.StandardOutput.ReadToEnd() | Should Be 2
            EnsureChildHasExited $process
        }
    }

    Context "Redirected standard input for 'interactive' use" {
        $nl = [Environment]::Newline

        # All of the following tests replace the prompt (either via an initial command or interactively)
        # so that we can read StandardOutput and reliably know exactly what the prompt is.

        It "Interactive redirected input: <InteractiveSwitch>" -TestCases @(
            @{InteractiveSwitch = ""}
            @{InteractiveSwitch = " -IntERactive"}
            @{InteractiveSwitch = " -i"}
        ) {
            param($interactiveSwitch)
            $si = NewProcessStartInfo "-noprofile -nologo$interactiveSwitch" -RedirectStdIn
            $process = RunPowerShell $si
            $process.StandardInput.Write("`$function:prompt = { 'PS> ' }`n")
            $null = $process.StandardOutput.ReadLine()
            $process.StandardInput.Write("1+1`n")
            $process.StandardOutput.ReadLine() | Should Be "PS> 1+1"
            $process.StandardOutput.ReadLine() | Should Be "2"
            $process.StandardInput.Write("1+2`n")
            $process.StandardOutput.ReadLine() | Should Be "PS> 1+2"
            $process.StandardOutput.ReadLine() | Should Be "3"

            # Backspace should work as expected
            $process.StandardInput.Write("1+2`b3`n")
            # A real console should render 2`b3 as just 3, but we're just capturing exactly what is written
            $process.StandardOutput.ReadLine() | Should Be "PS> 1+2`b3"
            $process.StandardOutput.ReadLine() | Should Be "4"
            $process.StandardInput.Close()
            $process.StandardOutput.ReadToEnd() | Should Be "PS> "
            EnsureChildHasExited $process
        }

        It "Interactive redirected input w/ initial command" {
            $si = NewProcessStartInfo "-noprofile -noexit -c ""`$function:prompt = { 'PS> ' }""" -RedirectStdIn
            $process = RunPowerShell $si
            $process.StandardInput.Write("1+1`n")
            $process.StandardOutput.ReadLine() | Should Be "PS> 1+1"
            $process.StandardOutput.ReadLine() | Should Be "2"
            $process.StandardInput.Write("1+2`n")
            $process.StandardOutput.ReadLine() | Should Be "PS> 1+2"
            $process.StandardOutput.ReadLine() | Should Be "3"
            $process.StandardInput.Close()
            $process.StandardOutput.ReadToEnd() | Should Be "PS> "
            EnsureChildHasExited $process
        }

        It "Redirected input explicit prompting (-File -)" {
            $si = NewProcessStartInfo "-noprofile -" -RedirectStdIn
            $process = RunPowerShell $si
            $process.StandardInput.Write("`$function:prompt = { 'PS> ' }`n")
            $null = $process.StandardOutput.ReadLine()
            $process.StandardInput.Write("1+1`n")
            $process.StandardOutput.ReadLine() | Should Be "PS> 1+1"
            $process.StandardOutput.ReadLine() | Should Be "2"
            $process.StandardInput.Close()
            $process.StandardOutput.ReadToEnd() | Should Be "PS> "
            EnsureChildHasExited $process
        }

        It "Redirected input no prompting (-Command -)" {
            $si = NewProcessStartInfo "-noprofile -Command -" -RedirectStdIn
            $process = RunPowerShell $si
            $process.StandardInput.Write("1+1`n")
            $process.StandardOutput.ReadLine() | Should Be "2"

            # Multi-line input
            $process.StandardInput.Write("if (1)`n{`n    42`n}`n`n")
            $process.StandardOutput.ReadLine() | Should Be "42"
            $process.StandardInput.Write(@"
function foo
{
    'in foo'
}

foo

"@)
            $process.StandardOutput.ReadLine() | Should Be "in foo"

            # Backspace sent through stdin should be in the final string
            $process.StandardInput.Write("`"a`bc`".Length`n")
            $process.StandardOutput.ReadLine() | Should Be "3"

            # Last command with no newline - should be accepted and
            # produce output after closing stdin.
            $process.StandardInput.Write('22 + 22')
            $process.StandardInput.Close()
            $process.StandardOutput.ReadLine() | Should Be "44"

            EnsureChildHasExited $process
        }

        It "Redirected input w/ nested prompt" {
            $si = NewProcessStartInfo "-noprofile -noexit -c ""`$function:prompt = { 'PS' + ('>'*(`$nestedPromptLevel+1)) + ' ' }""" -RedirectStdIn
            $process = RunPowerShell $si
            $process.StandardInput.Write("`$host.EnterNestedPrompt()`n")
            $process.StandardOutput.ReadLine() | Should Be "PS> `$host.EnterNestedPrompt()"
            $process.StandardInput.Write("exit`n")
            $process.StandardOutput.ReadLine() | Should Be "PS>> exit"
            $process.StandardInput.Close()
            $process.StandardOutput.ReadToEnd() | Should Be "PS> "
            EnsureChildHasExited $process
        }
    }

    Context "Exception handling" {
        It "Should handle a CallDepthOverflow" {
            # Infinite recursion
            function recurse
            {
                recurse $args
            }

            try
            {
                recurse "args"
                Throw "Incorrect exception"
            }
            catch
            {
                $_.FullyQualifiedErrorId | Should Be "CallDepthOverflow"
            }
        }
    }

    Context "Data, Config, and Cache locations" {
        BeforeEach {
            $XDG_CACHE_HOME = $env:XDG_CACHE_HOME
            $XDG_DATA_HOME = $env:XDG_DATA_HOME
            $XDG_CONFIG_HOME = $env:XDG_CONFIG_HOME
        }

        AfterEach {
            $env:XDG_CACHE_HOME = $XDG_CACHE_HOME
            $env:XDG_DATA_HOME = $XDG_DATA_HOME
            $env:XDG_CONFIG_HOME = $XDG_CONFIG_HOME
        }

        It "Should start if Data, Config, and Cache location is not accessible" -skip:($IsWindows) {
            $env:XDG_CACHE_HOME = "/dev/cpu"
            $env:XDG_DATA_HOME = "/dev/cpu"
            $env:XDG_CONFIG_HOME = "/dev/cpu"
            $output = & $powershell -noprofile -Command { (get-command).count }
            [int]$output | Should BeGreaterThan 0
        }
    }

    Context "HOME environment variable" {
        It "Should start if HOME is not defined" -skip:($IsWindows) {
            bash -c "unset HOME;$powershell -c '1+1'" | Should BeExactly 2
        }
    }

    Context "PATH environment variable" {
        It "`$PSHOME should be in front so that powershell.exe starts current running PowerShell" {
            powershell -v | Should Match $psversiontable.GitCommitId
        }
    }

    Context "Ambiguous arguments" {
        It "Ambiguous argument '<testArg>' should return possible matches" -TestCases @(
            @{testArg="-no";expectedMatches=@("-nologo","-noexit","-noprofile","-noninteractive")},
            @{testArg="-format";expectedMatches=@("-inputformat","-outputformat")}
        ) {
            param($testArg, $expectedMatches)
            $output = & $powershell $testArg -File foo 2>&1
            $LASTEXITCODE | Should Be $ExitCodeBadCommandLineParameter
            $outString = [String]::Join(",", $output)
            foreach ($expectedMatch in $expectedMatches)
            {
                $outString | Should Match $expectedMatch
            }
        }
    }
}

Describe "WindowStyle argument" -Tag Feature {
    BeforeAll {
        $defaultParamValues = $PSDefaultParameterValues.Clone()
        $PSDefaultParameterValues["it:skip"] = !$IsWindows

        if ($IsWindows)
        {
            $ExitCodeBadCommandLineParameter = 64
            Add-Type -Name User32 -Namespace Test -MemberDefinition @"
public static WINDOWPLACEMENT GetPlacement(IntPtr hwnd)
{
    WINDOWPLACEMENT placement = new WINDOWPLACEMENT();
    placement.length = Marshal.SizeOf(placement);
    GetWindowPlacement(hwnd, ref placement);
    return placement;
}

[DllImport("user32.dll", SetLastError = true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool GetWindowPlacement(
    IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);

[Serializable]
[StructLayout(LayoutKind.Sequential)]
public struct WINDOWPLACEMENT
{
    public int length;
    public int flags;
    public ShowWindowCommands showCmd;
    public System.Drawing.Point ptMinPosition;
    public System.Drawing.Point ptMaxPosition;
    public System.Drawing.Rectangle rcNormalPosition;
}

public enum ShowWindowCommands : int
{
    Hidden = 0,
    Normal = 1,
    Minimized = 2,
    Maximized = 3,
}
"@
        }
    }

    AfterAll {
        $global:PSDefaultParameterValues = $defaultParamValues
    }

    It "-WindowStyle <WindowStyle> should work on Windows" -TestCases @(
            @{WindowStyle="Normal"},
            @{WindowStyle="Minimized"},
            @{WindowStyle="Maximized"}  # hidden doesn't work in CI/Server Core
        ) {
        param ($WindowStyle)
        $ps = Start-Process powershell -ArgumentList "-WindowStyle $WindowStyle -noexit -interactive" -PassThru
        $startTime = Get-Date
        $showCmd = "Unknown"
        while (((Get-Date) - $startTime).TotalSeconds -lt 10 -and $showCmd -ne $WindowStyle)
        {
            Start-Sleep -Milliseconds 100
            $showCmd = ([Test.User32]::GetPlacement($ps.MainWindowHandle)).showCmd
        }
        $showCmd | Should BeExactly $WindowStyle
        $ps | Stop-Process -Force
    }

    It "Invalid -WindowStyle returns error" {
        powershell -WindowStyle invalid
        $LASTEXITCODE | Should Be $ExitCodeBadCommandLineParameter
    }
}

Describe "Console host api tests" -Tag CI {
    Context "String escape sequences" {
        $esc = [char]0x1b
        $testCases =
            @{InputObject = "abc"; Length = 3; Name = "No escapes"},
            @{InputObject = "${esc} [31mabc"; Length = 9; Name = "Malformed escape - extra space"},
            @{InputObject = "${esc}abc"; Length = 4; Name = "Malformed escape - no csi"},
            @{InputObject = "[31mabc"; Length = 7; Name = "Malformed escape - no escape"}

        $testCases += if ($host.UI.SupportsVirtualTerminal)
        {
            @{InputObject = "$esc[31mabc"; Length = 3; Name = "Escape at start"}
            @{InputObject = "$esc[31mabc$esc[0m"; Length = 3; Name = "Escape at start and end"}
        }
        else
        {
            @{InputObject = "$esc[31mabc"; Length = 8; Name = "Escape at start - no virtual term support"}
            @{InputObject = "$esc[31mabc$esc[0m"; Length = 12; Name = "Escape at start and end - no virtual term support"}
        }

        It "Should properly calculate buffer cell width of '<Name>'" -TestCases $testCases {
            param($InputObject, $Length)
            $host.UI.RawUI.LengthInBufferCells($InputObject) | Should Be $Length
        }
    }
}
