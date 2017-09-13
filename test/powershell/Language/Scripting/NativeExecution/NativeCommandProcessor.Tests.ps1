Describe 'native commands with pipeline' -tags 'Feature' {

    BeforeAll {
        $powershell = Join-Path -Path $PsHome -ChildPath "powershell"
    }

    It "native | ps | native doesn't block" {
        $iss = [initialsessionstate]::CreateDefault2();
        $rs = [runspacefactory]::CreateRunspace($iss)
        $rs.Open()

        $ps = [powershell]::Create()
        $ps.Runspace = $rs

        $ps.AddScript("& $powershell -noprofile -command '100;
            Start-Sleep -Seconds 100' |
            ForEach-Object { if (`$_ -eq 100) { 'foo'; exit; }}").BeginInvoke()

        # waiting 30 seconds, because powershell startup time could be long on the slow machines,
        # such as CI
        Wait-UntilTrue { $rs.RunspaceAvailability -eq 'Available' } -timeout 30000 -interval 100 | Should Be $true

        $ps.Stop()
        $rs.ResetRunspaceState()
    }

    It "native | native | native should work fine" {

        if ($IsWindows) {
            $result = @(ping.exe | findstr.exe count | findstr.exe ping)
            $result[0] | Should Match "Usage: ping"
        } else {
            $result = @(ps aux | grep powershell | grep -v grep)
            $result[0] | Should Match "powershell"
        }
    }
}

Describe "Native Command Processor" -tags "Feature" {

    # If powershell receives a StopProcessing, it should kill the native process and all child processes
    # this test should pass and no longer Pending when #2561 is fixed
    It "Should kill native process tree" -Pending {

        # make sure no test processes are running
        Get-Process testexe -ErrorAction SilentlyContinue | Stop-Process

        [int] $numToCreate = 2

        $ps = [PowerShell]::Create().AddCommand("testexe")
        $ps.AddArgument("-createchildprocess")
        $ps.AddArgument($numToCreate)
        $async = $ps.BeginInvoke()
        $ps.InvocationStateInfo.State | Should Be "Running"

        [bool] $childrenCreated = $false
        while (-not $childrenCreated)
        {
            $childprocesses = Get-Process testexe -ErrorAction SilentlyContinue
            if ($childprocesses.count -eq $numToCreate+1)
            {
                $childrenCreated = $true
            }
        }

        $startTime = Get-Date
        $beginsync = $ps.BeginStop($null, $async)
        # wait no more than 5 secs for the processes to be terminated, otherwise test has failed
        while (((Get-Date) - $startTime).TotalSeconds -lt 5)
        {
            if (($childprocesses.hasexited -eq $true).count -eq $numToCreate+1)
            {
                break
            }
        }
        $childprocesses = Get-Process testexe
        $count = $childprocesses.count
        $childprocesses | Stop-Process
        $count | Should Be 0
    }

    It "Should not block running Windows executables" -Skip:(!$IsWindows -or !(Get-Command notepad.exe)) {
        function FindNewNotepad
        {
            Get-Process -Name notepad -ErrorAction Ignore | Where-Object { $_.Id -notin $dontKill }
        }

        # We need to kill the windows process we start and can't know the process id, so get a list of
        # notepad processes already running and don't kill any of those.
        $dontKill = Get-Process -Name notepad -ErrorAction Ignore | ForEach-Object { $_.Id }

        try
        {
            $ps = [powershell]::Create().AddScript('notepad.exe; "ran notepad"')
            $async = $ps.BeginInvoke()

            # Wait for up to 30 seconds for either the pipeline to finish (should mean the test succeeded) or
            # for a new instance of notepad to have started (which mean we're blocked)
            $counter = 0
            while (!$async.AsyncWaitHandle.WaitOne(10000) -and $counter -lt 3 -and !(FindNewNotepad))
            {
                $counter++
            }

            # Stop the new instance of notepad
            $newNotepad = FindNewNotepad
            $newNotepad | Should Not Be $null
            $newNotepad | Stop-Process

            $async.IsCompleted | Should Be $true
            $ps.EndInvoke($async) | Should Be "ran notepad"
        }
        finally
        {
            if (!$async.IsCompleted)
            {
                $ps.Stop()
            }
            $ps.Dispose()
        }
    }
}

Describe "Open a text file with NativeCommandProcessor" -tags @("Feature", "RequireAdminOnWindows") {
    BeforeAll {
        if ($IsWindows) {
            $TestFile = Join-Path -Path $TestDrive -ChildPath "TextFileTest.foo"
        } else {
            $TestFile = Join-Path -Path $TestDrive -ChildPath "TextFileTest.txt"
        }
        Set-Content -Path $TestFile -Value "Hello" -Force
        $supportedEnvironment = $true

        if ($IsLinux) {
            $appFolder = "$HOME/.local/share/applications"
            $supportedEnvironment = Test-Path $appFolder
            if ($supportedEnvironment) {
                $mimeDefault = xdg-mime query default text/plain
                Remove-Item $HOME/nativeCommandProcessor.Success -Force -ErrorAction SilentlyContinue
                Set-Content -Path "$appFolder/nativeCommandProcessor.desktop" -Force -Value @"
[Desktop Entry]
Version=1.0
Name=nativeCommandProcessor
Comment=Validate_native_command_processor_open_text_file
Exec=/bin/sh -c 'echo %u > ~/nativeCommandProcessor.Success'
Icon=utilities-terminal
Terminal=true
Type=Application
Categories=Application;
"@
                xdg-mime default nativeCommandProcessor.desktop text/plain
            }
        }
        elseif ($IsWindows) {
            $supportedEnvironment = [System.Management.Automation.Platform]::IsWindowsDesktop
            if ($supportedEnvironment) {
                cmd /c assoc .foo=foofile
                cmd /c ftype foofile=cmd /c echo %1^> $TestDrive\foo.txt
                Remove-Item $TestDrive\foo.txt -Force -ErrorAction SilentlyContinue
            }
        }
    }

    AfterAll {
        Remove-Item -Path $TestFile -Force -ErrorAction SilentlyContinue

        if ($IsLinux -and $supportedEnvironment) {
            xdg-mime default $mimeDefault text/plain
            Remove-Item $appFolder/nativeCommandProcessor.desktop -Force -ErrorAction SilentlyContinue
            Remove-Item $HOME/nativeCommandProcessor.Success -Force -ErrorAction SilentlyContinue
        }
        elseif ($IsWindows -and $supportedEnvironment) {
            cmd /c assoc .foo=
            cmd /c ftype foofile=
        }
    }

    It "Should open text file without error" -Skip:(!$supportedEnvironment) {
        if ($IsMacOS) {
            $expectedTitle = Split-Path $TestFile -Leaf
            open -F -a TextEdit
            $beforeCount = [int]('tell application "TextEdit" to count of windows' | osascript)
            & $TestFile
            $startTime = Get-Date
            $title = [String]::Empty
            while (((Get-Date) - $startTime).TotalSeconds -lt 30 -and ($title -ne $expectedTitle)) {
                Start-Sleep -Milliseconds 100
                $title = 'tell application "TextEdit" to get name of front window' | osascript
            }
            $afterCount = [int]('tell application "TextEdit" to count of windows' | osascript)
            $afterCount | Should Be ($beforeCount + 1)
            $title | Should Be $expectedTitle
            "tell application ""TextEdit"" to close window ""$expectedTitle""" | osascript
            'tell application "TextEdit" to quit' | osascript
        }
        elseif ($IsLinux) {
            # Validate on Linux by reassociating default app for text file
            & $TestFile
            # It may take time for handler to start
            Wait-FileToBePresent -File "$HOME/nativeCommandProcessor.Success" -TimeoutInSeconds 10 -IntervalInMilliseconds 100
            Get-Content $HOME/nativeCommandProcessor.Success | Should Be $TestFile
        }
        else {
            & $TestFile
            Wait-FileToBePresent -File $TestDrive\foo.txt -TimeoutInSeconds 10 -IntervalInMilliseconds 100
            "$TestDrive\foo.txt" | Should Exist
            Get-Content $TestDrive\foo.txt | Should BeExactly $TestFile
        }
    }

    It "Opening a file with an unregistered extension on Windows should fail" -Skip:(!$IsWindows) {
        { $dllFile = "$PSHOME\System.Management.Automation.dll"; & $dllFile } | ShouldBeErrorId "NativeCommandFailed"
    }
}
