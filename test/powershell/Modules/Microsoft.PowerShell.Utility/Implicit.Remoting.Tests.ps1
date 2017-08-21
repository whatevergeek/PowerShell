﻿Describe "Implicit remoting and CIM cmdlets with AllSigned and Restricted policy" -tags "Feature" {

    BeforeAll {

        # Skip test for non-windows machines
        $skipTest = !$IsWindows

        if ($skipTest) { return }

        #
        # GET CERTIFICATE
        #

        $tempName = "$env:TEMP\signedscript_$(Get-Random).ps1"
        "123456" > $tempName
        $cert = $null
        foreach ($thisCertificate in (Get-ChildItem cert:\ -rec -codesigning))
        {
	        $null = Set-AuthenticodeSignature $tempName -Certificate $thisCertificate
	        if ((Get-AuthenticodeSignature $tempName).Status -eq "Valid")
	        {
		        $cert = $thisCertificate
		        break
	        }
        }

        # Skip the tests if we couldn't find a code sign certificate
        # This will happen in NanoServer and IoT
        if ($null -eq $cert)
        {
            $skipTest = $true
            return
        }

        # Ensure the cert is trusted
        if (-not (Test-Path "cert:\currentuser\TrustedPublisher\$($cert.Thumbprint)"))
        {
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store "TrustedPublisher"
            $store.Open("ReadWrite")
            $store.Add($cert)
            $store.Close()
        }

        #
        # Set process scope execution policy to 'AllSigned'
        #

        $oldExecutionPolicy = Get-ExecutionPolicy -Scope Process
        Set-ExecutionPolicy AllSigned -Scope Process

        #
        # Create a remote session
        #

        $session = New-RemoteSession
    }

    AfterAll {
        if ($skipTest) { return }

        if ($null -ne $tempName) { Remove-Item -Path $tempName -Force -ErrorAction SilentlyContinue }
        if ($null -ne $oldExecutionPolicy) { Set-ExecutionPolicy $oldExecutionPolicy -Scope Process }
        if ($null -ne $session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
    }

    #
    # TEST - Verifying that Import-PSSession signs the files
    #

    It "Verifies that Import-PSSession works in AllSigned if Certificate is used" -Skip:$skipTest {
        try {
            $importedModule = Import-PSSession $session Get-Variable -Prefix Remote -Certificate $cert -AllowClobber
    	    $importedModule | Should Not Be $null
        } finally {
            $importedModule | Remove-Module -Force -ErrorAction SilentlyContinue
        }
    }

    It "Verifies security error when Certificate parameter is not used" -Skip:$skipTest {
        try {
            $importedModule = Import-PSSession $session Get-Variable -Prefix Remote -AllowClobber
            throw "expect Import-PSSession to throw"
        } catch {
            $_.FullyQualifiedErrorId | Should Be "InvalidOperation,Microsoft.PowerShell.Commands.ImportPSSessionCommand"
        }
    }
}

Describe "Tests Import-PSSession cmdlet works with types unavailable on the client" -tags "Feature" {

    BeforeAll {

        # Skip test for non-windows machines for now
        $skipTest = !$IsWindows

        if ($skipTest) { return }

        $typeDefinition = @"
            namespace MyTest
            {
	            public enum MyEnum
	            {
		            Value1 = 1,
		            Value2 = 2
	            }
            }
"@
        #
        # Create a remote session
        #

        $session = New-RemoteSession

        Invoke-Command -Session $session -Script { Add-Type -TypeDefinition $args[0] } -Args $typeDefinition
        Invoke-Command -Session $session -Script { function foo { param([MyTest.MyEnum][Parameter(Mandatory = $true)]$x) $x } }
    }

    AfterAll {
        if ($skipTest) { return }
        if ($null -ne $session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
    }

    It "Verifies client-side unavailable enum is correctly handled" -Skip:$skipTest {
        try {
            $module = Import-PSSession -Session $session -CommandName foo -AllowClobber

            # The enum is treated as an int
            (foo -x "Value2") | Should Be 2
            # The enum is to-string-ed appropriately
            (foo -x "Value2").ToString() | Should Be "Value2"
        } finally {
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe "Cmdlet help from remote session" -tags "Feature" {

    BeforeAll {

        # Skip test for non-windows machines for now
        $skipTest = !$IsWindows

        if ($skipTest) { return }
        $session = New-RemoteSession
    }

    AfterAll {
        if ($skipTest) { return }
        if ($null -ne $session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
    }

    It "Verifies that get-help name for remote proxied commands matches the get-command name" -Skip:$skipTest {
        try {
            $module = Import-PSSession $session -Name Select-Object -prefix My -AllowClobber
            $gcmOutPut = (Get-Command Select-MyObject ).Name
            $getHelpOutPut = (Get-Help Select-MyObject).Name

            $gcmOutPut | Should Be $getHelpOutPut
        } finally {
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }
	}
}

Describe "Import-PSSession Cmdlet error handling" -tags "Feature" {

    BeforeAll {

        # Skip test for non-windows machines for now
        $skipTest = !$IsWindows

        if ($skipTest) { return }
        $session = New-RemoteSession
    }

    AfterAll {
        if ($skipTest) { return }
        if ($null -ne $session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
    }


    It "Verifies that broken alias results in one error" -Skip:$skipTest {
        try {
            Invoke-Command $session { Set-Alias BrokenAlias NonExistantCommand }
            $module = Import-PSSession $session -CommandName:BrokenAlias -CommandType:All -ErrorAction SilentlyContinue -ErrorVariable expectedError -AllowClobber

            $expectedError | Should Not Be NullOrEmpty
            $expectedError[0].ToString().Contains("BrokenAlias") | Should Be $true
        } finally {
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
            Invoke-Command $session { Remove-Item alias:BrokenAlias }
        }
    }

    Context "Test content and format of proxied error message (Windows 7: #319080)" {

        BeforeAll {
            if ($skipTest) { return }
            $module = Import-PSSession -Session $session -Name Get-Variable -Prefix My -AllowClobber
        }

        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Test non-terminating error" -Skip:$skipTest {
            $results = Get-MyVariable blah,pid 2>&1

            ($results[1]).Value | Should Not Be $PID  # Verifies that returned PID is not for this session

            $errorString = $results[0] | Out-String   # Verifies error message for variable blah
            ($errorString -like "*VariableNotFound*") | Should Be $true
        }

        It "Test terminating error" -Skip:$skipTest {
            $results = Get-MyVariable pid -Scope blah 2>&1

            $results.Count | Should Be 1              # Verifies that remote session pid is not returned

            $errorString = $results[0] | Out-String   # Verifes error message for incorrect Scope parameter argument
            ($errorString -like "*Argument*") | Should Be $true
        }
    }

    Context "Ordering of a sequence of error and output messages (Windows 7: #405065)" {

        BeforeAll {
            if ($skipTest) { return }

            Invoke-Command $session { function foo1{1; write-error 2; 3; write-error 4; 5; write-error 6} }
            $module = Import-PSSession $session -CommandName foo1 -AllowClobber

            $icmErr = $($icmOut = Invoke-Command $session { foo1 }) 2>&1
            $proxiedErr = $($proxiedOut = foo1) 2>&1
            $proxiedOut2 = foo1 2>$null

            $icmOut = "$icmOut"
            $icmErr = "$icmErr"
            $proxiedOut = "$proxiedOut"
            $proxiedOut2 = "$proxiedOut2"
            $proxiedErr = "$proxiedErr"
        }

        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Verifies proxied output = proxied output 2" -Skip:$skipTest {
            $proxiedOut2 | Should Be $proxiedOut
        }

        It "Verifies proxied output = icm output (for mixed error and output results)" -Skip:$skipTest {
            $icmOut | Should Be $proxiedOut
        }

        It "Verifies proxied error = icm error (for mixed error and output results)" -Skip:$skipTest {
            $icmErr | Should Be $proxiedErr
        }

        It "Verifies proxied order = icm order (for mixed error and output results)" -Skip:$skipTest {
            $icmOrder = Invoke-Command $session { foo1 } 2>&1 | out-string
            $proxiedOrder = foo1 2>&1 | out-string

            $icmOrder | Should Be $proxiedOrder
        }
    }

    Context "WarningVariable parameter works with implicit remoting (Windows 8: #44861)" {

        BeforeAll {
            if ($skipTest) { return }
            $module = Import-PSSession $session -CommandName Write-Warning -Prefix Remote -AllowClobber
        }

        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Verifies WarningVariable" -Skip:$skipTest {
            $global:myWarningVariable = @()
            Write-RemoteWarning MyWarning -WarningVariable global:myWarningVariable
            ([string]($myWarningVariable[0])) | Should Be 'MyWarning'
	    }
    }
}

Describe "Tests Export-PSSession" -tags "Feature" {

    BeforeAll {

        # Skip test for non-windows machines for now
        $skipTest = !$IsWindows

        if ($skipTest) { return }

        $sessionOption = New-PSSessionOption -ApplicationArguments @{myTest="MyValue"}
        $session = New-RemoteSession -SessionOption $sessionOption

        $file = [IO.Path]::Combine([IO.Path]::GetTempPath(), [Guid]::NewGuid().ToString())
        $results = Export-PSSession -Session $session -CommandName Get-Variable -AllowClobber -ModuleName $file
        $oldTimestamp = $($results | Select-Object -First 1).LastWriteTime
    }

    AfterAll {
        if ($skipTest) { return }
        if ($null -ne $file) { Remove-Item $file -Force -Recurse -ErrorAction SilentlyContinue }
        if ($null -ne $session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
    }

    It "Verifies Export-PSSession creates a file/directory" -Skip:$skipTest {
        @(Get-Item $file).Count | Should Be 1
    }

    It "Verifies Export-PSSession creates a psd1 file" -Skip:$skipTest {
        ($results | Where-Object { $_.Name -like "*$(Split-Path -Leaf $file).psd1" }) | Should Be $true
    }

    It "Verifies Export-PSSession creates a psm1 file" -Skip:$skipTest {
        ($results | Where-Object { $_.Name -like "*.psm1" }) | Should Be $true
    }

    It "Verifies Export-PSSession creates a ps1xml file" -Skip:$skipTest {
        ($results | Where-Object { $_.Name -like "*.ps1xml" }) | Should Be $true
    }

    It "Verifies that Export-PSSession fails when a module directory already exists" -Skip:$skipTest {
        try {
            Export-PSSession -Session $session -CommandName Get-Variable -AllowClobber -ModuleName $file -EA SilentlyContinue -ErrorVariable expectedError
        } catch { }

        $expectedError | Should Not Be NullOrEmpty
        # Error contains reference to the directory that already exists
        ([string]($expectedError[0]) -like "*$file*") | Should Be $true
    }

    It "Verifies that overwriting an existing directory succeeds with -Force" -Skip:$skipTest {
        $newResults = Export-PSSession -Session $session -CommandName Get-Variable -AllowClobber -ModuleName $file -Force

        # Verifies that Export-PSSession returns 4 files
        @($newResults).Count | Should Be 4

        # Verifies that Export-PSSession creates *new* files
        $newResults | ForEach-Object { $_.LastWriteTime | Should BeGreaterThan $oldTimestamp }
    }

    Context "The module is usable when the original runspace is still around" {

        BeforeAll {
            if ($skipTest) { return }
            $module = Import-Module $file -PassThru
        }

        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Verifies that proxy returns remote pid" -Skip:$skipTest {
            (Get-Variable -Name pid).Value | Should Not Be $pid
        }

	    It "Verfies Remove-Module doesn't remove user's runspace" -Skip:$skipTest {
            Remove-Module $module -Force -ErrorAction SilentlyContinue
            (Get-PSSession -InstanceId $session.InstanceId) | Should Not Be NullOrEmpty
        }
    }
}

Describe "Proxy module is usable when the original runspace is no longer around" -tags "Feature" {
    BeforeAll {
        # Run the tests only in FullCLR powershell because implicit credential doesn't work in AppVeyor builder
        $skipTest = !$IsWindows -or $IsCoreCLR

        if ($skipTest) { return }

        $sessionOption = New-PSSessionOption -ApplicationArguments @{myTest="MyValue"}
        $session = New-RemoteSession -SessionOption $sessionOption

        $file = [IO.Path]::Combine([IO.Path]::GetTempPath(), [Guid]::NewGuid().ToString())
        $null = Export-PSSession -Session $session -CommandName Get-Variable -AllowClobber -ModuleName $file

        # Close the session to test the behavior of proxy module
        if ($null -ne $session) { Remove-PSSession $session -ErrorAction SilentlyContinue; $session = $null }
    }

    AfterAll {
        if ($skipTest) { return }
        if ($null -ne $file) { Remove-Item $file -Force -Recurse -ErrorAction SilentlyContinue }
        if ($null -ne $session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
    }

    ## It requires 'New-PSSession' to work with implicit credential to allow proxied command to create new session.
    ## Implicit credential doesn't work in AppVeyor builder, so mark all tests here '-pending'.

    Context "Proxy module should create a new session" {
        BeforeAll {
            if ($skipTest) { return }
            $module = import-Module $file -PassThru -Force
            $internalSession = & $module { $script:PSSession }
        }
        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Verifies proxy should return remote pid" -Pending {
            (Get-Variable -Name PID).Value | Should Not Be $PID
        }

        It "Verifies ApplicationArguments got preserved correctly" -Pending {
            $(Invoke-Command $internalSession { $PSSenderInfo.ApplicationArguments.MyTest }) | Should Be "MyValue"
        }

        It "Verifies Remove-Module removed the runspace that was automatically created" -Pending {
            Remove-Module $module -Force
            (Get-PSSession -InstanceId $internalSession.InstanceId -ErrorAction SilentlyContinue) | Should Be $null
        }

        It "Verifies Runspace is closed after removing module from Export-PSSession that got initialized with an internal r-space" -Pending {
            ($internalSession.Runspace.RunspaceStateInfo.ToString()) | Should Be "Closed"
        }
    }

    Context "Runspace created by the module with explicit session options" {
        BeforeAll {
            if ($skipTest) { return }
            $explicitSessionOption = New-PSSessionOption -Culture fr-FR -UICulture de-DE
            $module = import-Module $file -PassThru -Force -ArgumentList $null, $explicitSessionOption
            $internalSession = & $module { $script:PSSession }
        }
        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Verifies proxy should return remote pid" -Pending {
            (Get-Variable -Name PID).Value | Should Not Be $PID
        }

        # culture settings should be taken from the explicitly passed session options
        It "Verifies proxy returns modified culture" -Pending {
            (Get-Variable -Name PSCulture).Value | Should Be "fr-FR"
        }
        It "Verifies proxy returns modified culture" -Pending {
            (Get-Variable -Name PSUICulture).Value | Should Be "de-DE"
        }

        # removing the module should remove the implicitly/magically created runspace
        It "Verifies Remove-Module removes automatically created runspace" -Pending {
            Remove-Module $module -Force
            (Get-PSSession -InstanceId $internalSession.InstanceId -ErrorAction SilentlyContinue) | Should Be $null
        }
        It "Verifies Runspace is closed after removing module from Export-PSSession that got initialized with an internal r-space" -Pending {
            ($internalSession.Runspace.RunspaceStateInfo.ToString()) | Should Be "Closed"
        }
    }

    Context "Passing a runspace into proxy module" {
        BeforeAll {
            if ($skipTest) { return }

            $newSession = New-RemoteSession
            $module = import-Module $file -PassThru -Force -ArgumentList $newSession
            $internalSession = & $module { $script:PSSession }
        }
        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
            if ($null -ne $newSession) { Remove-PSSession $newSession -ErrorAction SilentlyContinue }
        }

        It "Verifies proxy returns remote pid" -Pending {
            (Get-Variable -Name PID).Value | Should Not Be $PID
        }

        It "Verifies switch parameters work" -Pending {
            (Get-Variable -Name PID -ValueOnly) | Should Not Be $PID
        }

        It "Verifies Adding a module affects runspace's state" -Pending {
            ($internalSession.Runspace.RunspaceStateInfo.ToString()) | Should Be "Opened"
        }

        It "Verifies Runspace stays opened after removing module from Export-PSSession that got initialized with an external runspace" -Pending {
            Remove-Module $module -Force
		    ($internalSession.Runspace.RunspaceStateInfo.ToString()) | Should Be "Opened"
	    }
    }
}

Describe "Import-PSSession with FormatAndTypes" -tags "Feature" {

    BeforeAll {
        # Skip test for non-windows machines for now
        $skipTest = !$IsWindows

        if ($skipTest) { return }
        $session = New-RemoteSession

        function CreateTempPs1xmlFile
        {
            do {
                $tmpFile = [IO.Path]::Combine([IO.Path]::GetTempPath(), [IO.Path]::GetRandomFileName()) + ".ps1xml";
            } while ([IO.File]::Exists($tmpFile))
            $tmpFile
        }

        function CreateTypeFile {
            $tmpFile = CreateTempPs1xmlFile
@"
    <Types>
	    <Type>
		<Name>System.Management.Automation.Host.Coordinates</Name>
		    <Members>
			    <NoteProperty>
				<Name>MyTestLabel</Name>
				<Value>123</Value>
			    </NoteProperty>
		    </Members>
	    </Type>
	    <Type>
		    <Name>MyTest.Root</Name>
		    <Members>
		    <MemberSet>
			<Name>PSStandardMembers</Name>
			<Members>
			    <NoteProperty>
				<Name>SerializationDepth</Name>
				<Value>1</Value>
			    </NoteProperty>
			</Members>
		        </MemberSet>
		    </Members>
	    </Type>
	    <Type>
		    <Name>MyTest.Son</Name>
		    <Members>
		    <MemberSet>
			<Name>PSStandardMembers</Name>
			<Members>
			    <NoteProperty>
				<Name>SerializationDepth</Name>
				<Value>1</Value>
			    </NoteProperty>
			</Members>
		        </MemberSet>
		    </Members>
	    </Type>
	    <Type>
		    <Name>MyTest.Grandson</Name>
		    <Members>
		    <MemberSet>
			<Name>PSStandardMembers</Name>
			<Members>
			    <NoteProperty>
				<Name>SerializationDepth</Name>
				<Value>1</Value>
			    </NoteProperty>
			</Members>
		        </MemberSet>
		    </Members>
	    </Type>
	</Types>
"@ | set-content $tmpFile
	        $tmpFile
        }

        function CreateFormatFile {
            $tmpFile = CreateTempPs1xmlFile
@"
    <Configuration>
	    <ViewDefinitions>
		<View>
		    <Name>MySizeView</Name>
		    <ViewSelectedBy>
			<TypeName>System.Management.Automation.Host.Size</TypeName>
		    </ViewSelectedBy>
		    <TableControl>
			<TableHeaders>
			    <TableColumnHeader>
				<Label>MyTestWidth</Label>
			    </TableColumnHeader>
			    <TableColumnHeader>
				<Label>MyTestHeight</Label>
			    </TableColumnHeader>
			</TableHeaders>
			<TableRowEntries>
			    <TableRowEntry>
				<TableColumnItems>
				    <TableColumnItem>
					<PropertyName>Width</PropertyName>
				    </TableColumnItem>
				    <TableColumnItem>
					<PropertyName>Height</PropertyName>
				    </TableColumnItem>
				</TableColumnItems>
			    </TableRowEntry>
			    </TableRowEntries>
		    </TableControl>
		</View>
	    </ViewDefinitions>
	</Configuration>
"@ | set-content $tmpFile
            $tmpFile
        }

        $formatFile = CreateFormatFile
        $typeFile = CreateTypeFile
    }

    AfterAll {
        if ($skipTest) { return }
        if ($null -ne $session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
        if ($null -ne $formatFile) { Remove-Item $formatFile -Force -ErrorAction SilentlyContinue }
        if ($null -ne $typeFile) { Remove-Item $typeFile -Force -ErrorAction SilentlyContinue }
    }

    Context "Importing format file works" {
        BeforeAll {
            if ($skipTest) { return }

            $formattingScript = { new-object System.Management.Automation.Host.Size | ForEach-Object { $_.Width = 123; $_.Height = 456; $_ } | Out-String }
            $originalLocalFormatting = & $formattingScript

            # Original local and remote formatting should be equal (sanity check)
            $originalRemoteFormatting = Invoke-Command $session $formattingScript
            $originalLocalFormatting | Should Be $originalRemoteFormatting

            Invoke-Command $session { param($file) Update-FormatData $file } -ArgumentList $formatFile

            # Original remote and modified remote formatting should not be equal (sanity check)
            $modifiedRemoteFormatting = Invoke-Command $session $formattingScript
            $originalRemoteFormatting | Should Not Be $modifiedRemoteFormatting

            $module = Import-PSSession -Session $session -CommandName @() -FormatTypeName * -AllowClobber
        }

        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "modified remote and imported local should be equal" -Skip:$skipTest {
            $importedLocalFormatting = & $formattingScript
            $modifiedRemoteFormatting | Should Be $importedLocalFormatting
        }

        It "original local and unimported local should be equal" -Skip:$skipTest {
            Remove-Module $module -Force
            $unimportedLocalFormatting = & $formattingScript
            $originalLocalFormatting | Should Be $unimportedLocalFormatting
        }
    }

    It "Updating type table in a middle of a command has effect on serializer" -Skip:$skipTest {
        $results = Invoke-Command $session -ArgumentList $typeFile -ScriptBlock {
            param($file)

            New-Object System.Management.Automation.Host.Coordinates
            Update-TypeData $file
            New-Object System.Management.Automation.Host.Coordinates
        }

        # Should get 2 deserialized S.M.A.H.Coordinates objects
        $results.Count | Should Be 2
        # First object shouldn't have the additional ETS note property
        $results[0].MyTestLabel | Should Be $null
        # Second object should have the additional ETS note property
        $results[1].MyTestLabel | Should Be 123
    }

    Context "Implicit remoting works even when types.ps1xml is missing on the client" {
        BeforeAll {
            if ($skipTest) { return }

            $typeDefinition = @"
                namespace MyTest
                {
                    public class Root
                    {
        	            public Root(string s) { text = s; }
        	            public Son Son = new Son();
        	            public string text;
                    }

                    public class Son
                    {
                        public Grandson Grandson = new Grandson();
                    }

                    public class Grandson
                    {
                        public string text = "Grandson";
    	            }
                }
"@
            Invoke-Command -Session $session -Script { Add-Type -TypeDefinition $args[0] } -ArgumentList $typeDefinition
            Invoke-Command -Session $session -Script { function foo { New-Object MyTest.Root "root" } }
            Invoke-Command -Session $session -Script { function bar { param([Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]$Son) $Son.Grandson.text } }

            $module = import-pssession $session foo,bar -AllowClobber
        }

        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Serialization works for top-level properties" -Skip:$skipTest {
            $x = foo
            $x.text | Should Be "root"
        }

        It "Serialization settings works for deep properties" -Skip:$skipTest {
            $x = foo
            $x.Son.Grandson.text | Should Be "Grandson"
        }

        It "Serialization settings are preserved even if types.ps1xml is missing on the client" -Skip:$skipTest {
            $y = foo | bar
            $y | Should Be "Grandson"
        }
    }
}

Describe "Import-PSSession functional tests" -tags "Feature" {

    BeforeAll {
        # Skip test for non-windows machines for now
        $skipTest = !$IsWindows

        if ($skipTest) { return }
        $session = New-RemoteSession

        # Define a remote function
        Invoke-Command -Session $session { function MyFunction { param($x) "x = '$x'; args = '$args'" } }

        # Define a remote proxy script cmdlet
        $remoteCommandType = $ExecutionContext.InvokeCommand.GetCommand('Get-Variable', [System.Management.Automation.CommandTypes]::Cmdlet)
        $remoteProxyBody = [System.Management.Automation.ProxyCommand]::Create($remoteCommandType)
        $remoteProxyDeclaration = "function Get-VariableProxy { $remoteProxyBody }"
        Invoke-Command -Session $session { param($x) Invoke-Expression $x } -Arg $remoteProxyDeclaration
        $remoteAliasDeclaration = "set-alias gvalias Get-Variable"
        Invoke-Command -Session $session { param($x) Invoke-Expression $x } -Arg $remoteAliasDeclaration
        Remove-Item alias:gvalias -Force -ErrorAction silentlycontinue

        # Import a remote function, script cmdlet, cmdlet, native application, alias
        $module = Import-PSSession -Session $session -Name MyFunction,Get-VariableProxy,Get-Variable,gvalias,cmd -AllowClobber -Type All
    }

    AfterAll {
        if ($skipTest) { return }
        if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        if ($null -ne $session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
    }

    It "Import-PSSession should return a PSModuleInfo object" -Skip:$skipTest {
        $module | Should Not Be NullOrEmpty
    }

    It "Import-PSSession should return a PSModuleInfo object" -Skip:$skipTest {
        ($module -as [System.Management.Automation.PSModuleInfo]) | Should Not Be NullOrEmpty
    }

    It "Helper functions should not be imported" -Skip:$skipTest {
        (Get-Item function:*PSImplicitRemoting* -ErrorAction SilentlyContinue) | Should Be $null
    }

    It "Calls implicit remoting proxies 'MyFunction'" -Skip:$skipTest {
        (MyFunction 1 2 3) | Should Be "x = '1'; args = '2 3'"
    }

    It "proxy should return remote pid" -Skip:$skipTest {
        (Get-VariableProxy -Name:pid).Value | Should Not Be $pid
    }

    It "proxy should return remote pid" -Skip:$skipTest {
        (Get-Variable -Name:pid).Value | Should Not Be $pid
    }

    It "proxy should return remote pid" -Skip:$skipTest {
        $(& (Get-Command gvalias -Type alias) -Name:pid).Value | Should Not Be $pid
    }

    It "NoName-c8aeb5c8-2388-4d64-98c1-a9c6c218d404" -Skip:$skipTest {
        Invoke-Command -Session $session { $env:TestImplicitRemotingVariable = 123 }
        (cmd.exe /c "echo TestImplicitRemotingVariable=%TestImplicitRemotingVariable%") | Should Be "TestImplicitRemotingVariable=123"
    }

    Context "Test what happens after the runspace is closed" {
        BeforeAll {
            if ($skipTest) { return }

            Remove-PSSession $session

            # The loop below works around the fact that PSEventManager uses threadpool worker to queue event handler actions to process later.
            # Usage of threadpool means that it is impossible to predict when the event handler will run (this is Windows 8 Bugs: #882977).
            $i = 0
            while ( ($i -lt 20) -and ($null -ne (Get-Module | Where-Object { $_.Path -eq $module.Path })) )
            {
                $i++
                Start-Sleep -Milliseconds 50
            }
        }

        It "Temporary module should be automatically removed after runspace is closed" -Skip:$skipTest {
            (Get-Module | Where-Object { $_.Path -eq $module.Path }) | Should Be $null
        }

        It "Temporary psm1 file should be automatically removed after runspace is closed" -Skip:$skipTest {
            (Get-Item $module.Path -ErrorAction SilentlyContinue) | Should Be $null
        }

        It "Event should be unregistered when the runspace is closed" -Skip:$skipTest {
            # Check that the implicit remoting event has been removed.
            $implicitEventCount = 0
            foreach ($item in $ExecutionContext.Events.Subscribers)
            {
                if ($item.SourceIdentifier -match "Implicit remoting event") { $implicitEventCount++ }
            }
            $implicitEventCount | Should Be 0
        }

        It "Private functions from the implicit remoting module shouldn't get imported into global scope" -Skip:$skipTest {
            @(Get-ChildItem function:*Implicit* -ErrorAction SilentlyContinue).Count | Should Be 0
        }
    }
}

Describe "Implicit remoting parameter binding" -tags "Feature" {

    BeforeAll {
        # Skip test for non-windows machines for now
        $skipTest = !$IsWindows

        if ($skipTest) { return }
        $session = New-RemoteSession
    }

    AfterAll {
        if ($skipTest) { return }
        if ($null -ne $session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
    }

    It "Binding of ValueFromPipeline should work" -Skip:$skipTest {
        try {
            $module = Import-PSSession -Session $session -Name Get-Random -AllowClobber
            $x = 1..20 | Get-Random -Count 5
            $x.Count | Should Be 5
        } finally {
            Remove-Module $module -Force
        }
    }

    Context "Pipeline-based parameter binding works even when client has no type constraints (Windows 7: #391157)" {
        BeforeAll {
            if ($skipTest) { return }

            Invoke-Command -Session $session -ScriptBlock {
                function foo {
                    [cmdletbinding(defaultparametersetname="string")]
                    param(
                        [string]
                        [parameter(ParameterSetName="string", ValueFromPipeline = $true)]
                        $string,

                        [ipaddress]
                        [parameter(ParameterSetName="ipaddress", ValueFromPipeline = $true)]
                        $ipaddress
                    )

                    "Bound parameter: $($myInvocation.BoundParameters.Keys | sort)"
                }
            }

            # Sanity checks.
            Invoke-Command $session {"s" | foo} | Should Be "Bound parameter: string"
            Invoke-Command $session {[ipaddress]::parse("127.0.0.1") | foo} | Should Be "Bound parameter: ipaddress"

            $module = Import-PSSession $session foo -AllowClobber
        }

        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Pipeline binding works even if it relies on type constraints" -Skip:$skipTest {
            ("s" | foo) | Should Be "Bound parameter: string"
        }

        It "Pipeline binding works even if it relies on type constraints" -Skip:$skipTest {
            ([ipaddress]::parse("127.0.0.1") | foo) | Should Be "Bound parameter: ipaddress"
        }
    }

    Context "Pipeline-based parameter binding works even when client has no type constraints and parameterset is ambiguous (Windows 7: #430379)" {
        BeforeAll {
            if ($skipTest) { return }

            Invoke-Command -Session $session -ScriptBlock {
                function foo {
                    param(
                        [string]
                        [parameter(ParameterSetName="string", ValueFromPipeline = $true)]
                        $string,

                        [ipaddress]
                        [parameter(ParameterSetName="ipaddress", ValueFromPipeline = $true)]
                        $ipaddress
                    )

                    "Bound parameter: $($myInvocation.BoundParameters.Keys)"
                }
            }

            # Sanity checks.
            Invoke-Command $session {"s" | foo} | Should Be "Bound parameter: string"
            Invoke-Command $session {[ipaddress]::parse("127.0.0.1") | foo} | Should Be "Bound parameter: ipaddress"

            $module = Import-PSSession $session foo -AllowClobber
        }

        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Pipeline binding works even if it relies on type constraints and parameter set is ambiguous" -Skip:$skipTest {
            ("s" | foo) | Should Be "Bound parameter: string"
        }

        It "Pipeline binding works even if it relies on type constraints and parameter set is ambiguous" -Skip:$skipTest {
            ([ipaddress]::parse("127.0.0.1") | foo) | Should Be "Bound parameter: ipaddress"
        }
    }

    Context "pipeline-based parameter binding works even when one of parameters that can be bound by pipeline gets bound by name" {
        BeforeAll {
            if ($skipTest) { return }

            Invoke-Command -Session $session -ScriptBlock {
                function foo {
                    param(
                        [DateTime]
                        [parameter(ValueFromPipeline = $true)]
                        $date,

                        [ipaddress]
                        [parameter(ValueFromPipeline = $true)]
                        $ipaddress
                    )

                    "Bound parameter: $($myInvocation.BoundParameters.Keys | sort)"
                }
            }

            # Sanity checks.
            Invoke-Command $session {Get-Date | foo} | Should Be "Bound parameter: date"
            Invoke-Command $session {[ipaddress]::parse("127.0.0.1") | foo} | Should Be "Bound parameter: ipaddress"
            Invoke-Command $session {[ipaddress]::parse("127.0.0.1") | foo -date (get-date)} | Should Be "Bound parameter: date ipaddress"
            Invoke-Command $session {Get-Date | foo -ipaddress ([ipaddress]::parse("127.0.0.1"))} | Should Be "Bound parameter: date ipaddress"

            $module = Import-PSSession $session foo -AllowClobber
        }

        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Pipeline binding works even when also binding by name" -Skip:$skipTest {
            (Get-Date | foo) | Should Be "Bound parameter: date"
        }

        It "Pipeline binding works even when also binding by name" -Skip:$skipTest {
            ([ipaddress]::parse("127.0.0.1") | foo) | Should Be "Bound parameter: ipaddress"
        }

        It "Pipeline binding works even when also binding by name" -Skip:$skipTest {
            ([ipaddress]::parse("127.0.0.1") | foo -date $(Get-Date)) | Should Be "Bound parameter: date ipaddress"
        }

        It "Pipeline binding works even when also binding by name" -Skip:$skipTest {
    	    (Get-Date | foo -ipaddress ([ipaddress]::parse("127.0.0.1"))) | Should Be "Bound parameter: date ipaddress"
        }
    }

    Context "value from pipeline by property name - multiple parameters" {
        BeforeAll {
            if ($skipTest) { return }

            Invoke-Command -Session $session -ScriptBlock {
                function foo {
                    param(
                        [System.TimeSpan]
                        [parameter(ValueFromPipelineByPropertyName = $true)]
                        $TotalProcessorTime,

                        [System.Diagnostics.ProcessPriorityClass]
                        [parameter(ValueFromPipelineByPropertyName = $true)]
                        $PriorityClass
                    )

                    "Bound parameter: $($myInvocation.BoundParameters.Keys | sort)"
                }
            }

            # Sanity checks.
            Invoke-Command $session {gps -pid $pid | foo} | Should Be "Bound parameter: PriorityClass TotalProcessorTime"
            Invoke-Command $session {gps -pid $pid | foo -Total 5} | Should Be "Bound parameter: PriorityClass TotalProcessorTime"
            Invoke-Command $session {gps -pid $pid | foo -Priority normal} | Should Be "Bound parameter: PriorityClass TotalProcessorTime"

            $module = Import-PSSession $session foo -AllowClobber
        }

        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Pipeline binding works by property name" -Skip:$skipTest {
            (gps -id $pid | foo) | Should Be "Bound parameter: PriorityClass TotalProcessorTime"
        }

        It "Pipeline binding works by property name" -Skip:$skipTest {
            (gps -id $pid | foo -Total 5) | Should Be "Bound parameter: PriorityClass TotalProcessorTime"
        }

        It "Pipeline binding works by property name" -Skip:$skipTest {
            (gps -id $pid | foo -Priority normal) | Should Be "Bound parameter: PriorityClass TotalProcessorTime"
        }
    }

    Context "2 parameters on the same position" {
        BeforeAll {
            if ($skipTest) { return }

            Invoke-Command -Session $session -ScriptBlock {
                function foo {
                    param(
                        [string]
                        [parameter(Position = 0, parametersetname = 'set1', mandatory = $true)]
                        $string,

                        [ipaddress]
                        [parameter(Position = 0, parametersetname = 'set2', mandatory = $true)]
                        $ipaddress
                    )

                    "Bound parameter: $($myInvocation.BoundParameters.Keys | sort)"
                }
            }

            # Sanity checks.
            Invoke-Command $session {foo ([ipaddress]::parse("127.0.0.1"))} | Should Be "Bound parameter: ipaddress"
            Invoke-Command $session {foo "blah"} | Should Be "Bound parameter: string"

            $module = Import-PSSession $session foo -AllowClobber
        }

        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Positional binding works" -Skip:$skipTest {
            foo "blah" | Should Be "Bound parameter: string"
        }

        It "Positional binding works" -Skip:$skipTest {
            foo ([ipaddress]::parse("127.0.0.1")) | Should Be "Bound parameter: ipaddress"
        }
    }

    Context "positional binding and array argument value" {
        BeforeAll {
            if ($skipTest) { return }

            Invoke-Command -Session $session -ScriptBlock {
                function foo {
                    param(
                        [object]
                        [parameter(Position = 0, mandatory = $true)]
                        $p1,

                        [object]
                        [parameter(Position = 1)]
                        $p2
                    )

                    "$p1 : $p2"
                }
            }

            # Sanity checks.
            Invoke-Command $session {foo 1,2,3} | Should Be "1 2 3 : "
            Invoke-Command $session {foo 1,2,3 4} | Should Be "1 2 3 : 4"
            Invoke-Command $session {foo -p2 4 1,2,3} | Should Be "1 2 3 : 4"
            Invoke-Command $session {foo 1 4} | Should Be "1 : 4"
            Invoke-Command $session {foo -p2 4 1} | Should Be "1 : 4"

            $module = Import-PSSession $session foo -AllowClobber
        }

        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Positional binding works when binding an array value" -Skip:$skipTest {
            foo 1,2,3 | Should Be "1 2 3 : "
        }

        It "Positional binding works when binding an array value" -Skip:$skipTest {
            foo 1,2,3 4 | Should Be "1 2 3 : 4"
        }

        It "Positional binding works when binding an array value" -Skip:$skipTest {
            foo -p2 4 1,2,3 | Should Be "1 2 3 : 4"
        }

        It "Positional binding works when binding an array value" -Skip:$skipTest {
            foo 1 4 | Should Be "1 : 4"
        }

        It "Positional binding works when binding an array value" -Skip:$skipTest {
            foo -p2 4 1 | Should Be "1 : 4"
        }
    }

    Context "value from remaining arguments" {
        BeforeAll {
            if ($skipTest) { return }

            Invoke-Command -Session $session -ScriptBlock {
                function foo {
                    param(
                        [string]
                        [parameter(Position = 0)]
                        $firstArg,

                        [string[]]
                        [parameter(ValueFromRemainingArguments = $true)]
                        $remainingArgs
                    )

                    "$firstArg : $remainingArgs"
                }
            }

            # Sanity checks.
            Invoke-Command $session {foo} | Should Be " : "
            Invoke-Command $session {foo 1} | Should Be "1 : "
            Invoke-Command $session {foo -first 1} | Should Be "1 : "
            Invoke-Command $session {foo 1 2 3} | Should Be "1 : 2 3"
            Invoke-Command $session {foo -first 1 2 3} | Should Be "1 : 2 3"
            Invoke-Command $session {foo 2 3 -first 1 4 5} | Should Be "1 : 2 3 4 5"
            Invoke-Command $session {foo -remainingArgs 2,3 1} | Should Be "1 : 2 3"

            $module = Import-PSSession $session foo -AllowClobber
        }

        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Value from remaining arguments works" -Skip:$skipTest {
            $( foo ) | Should Be " : "
        }

        It "Value from remaining arguments works" -Skip:$skipTest {
            $( foo 1 ) | Should Be "1 : "
        }

        It "Value from remaining arguments works" -Skip:$skipTest {
            $( foo -first 1 ) | Should Be "1 : "
        }

        It "Value from remaining arguments works" -Skip:$skipTest {
            $( foo 1 2 3 ) | Should Be "1 : 2 3"
        }

        It "Value from remaining arguments works" -Skip:$skipTest {
            $( foo -first 1 2 3 ) | Should Be "1 : 2 3"
        }

        It "Value from remaining arguments works" -Skip:$skipTest {
            $( foo 2 3 -first 1 4 5 ) | Should Be "1 : 2 3 4 5"
        }

        It "Value from remaining arguments works" -Skip:$skipTest {
            $( foo -remainingArgs 2,3 1 ) | Should Be "1 : 2 3"
        }
    }

    Context "non cmdlet-based binding" {
        BeforeAll {
            if ($skipTest) { return }

            Invoke-Command -Session $session -ScriptBlock {
                function foo {
                    param(
                        $firstArg,
                        $secondArg
                    )

                    "$firstArg : $secondArg : $args"
                }
            }

            # Sanity checks.
            Invoke-Command $session { foo } | Should Be " :  : "
            Invoke-Command $session { foo 1 } | Should Be "1 :  : "
            Invoke-Command $session { foo -first 1 } | Should Be "1 :  : "
            Invoke-Command $session { foo 1 2 } | Should Be "1 : 2 : "
            Invoke-Command $session { foo 1 -second 2 } | Should Be "1 : 2 : "
            Invoke-Command $session { foo -first 1 -second 2 } | Should Be "1 : 2 : "
            Invoke-Command $session { foo 1 2 3 4 } | Should Be "1 : 2 : 3 4"
            Invoke-Command $session { foo -first 1 2 3 4 } | Should Be "1 : 2 : 3 4"
            Invoke-Command $session { foo 1 -second 2 3 4 } | Should Be "1 : 2 : 3 4"
            Invoke-Command $session { foo 1 3 -second 2 4 } | Should Be "1 : 2 : 3 4"
            Invoke-Command $session { foo -first 1 -second 2 3 4 } | Should Be "1 : 2 : 3 4"

            $module = Import-PSSession $session foo -AllowClobber
        }

        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Non cmdlet-based binding works." -Skip:$skipTest {
            foo | Should Be " :  : "
        }

        It "Non cmdlet-based binding works." -Skip:$skipTest {
            foo 1 | Should Be "1 :  : "
        }

        It "Non cmdlet-based binding works." -Skip:$skipTest {
            foo -first 1 | Should Be "1 :  : "
        }

        It "Non cmdlet-based binding works." -Skip:$skipTest {
            foo 1 2 | Should Be "1 : 2 : "
        }

        It "Non cmdlet-based binding works." -Skip:$skipTest {
            foo 1 -second 2 | Should Be "1 : 2 : "
        }

        It "Non cmdlet-based binding works." -Skip:$skipTest {
            foo -first 1 -second 2 | Should Be "1 : 2 : "
        }

        It "Non cmdlet-based binding works." -Skip:$skipTest {
            foo 1 2 3 4 | Should Be "1 : 2 : 3 4"
        }

        It "Non cmdlet-based binding works." -Skip:$skipTest {
            foo -first 1 2 3 4 | Should Be "1 : 2 : 3 4"
        }

        It "Non cmdlet-based binding works." -Skip:$skipTest {
            foo 1 -second 2 3 4 | Should Be "1 : 2 : 3 4"
        }

        It "Non cmdlet-based binding works." -Skip:$skipTest {
            foo 1 3 -second 2 4 | Should Be "1 : 2 : 3 4"
        }

        It "Non cmdlet-based binding works." -Skip:$skipTest {
            foo -first 1 -second 2 3 4 | Should Be "1 : 2 : 3 4"
        }
    }

    Context "default parameter initialization should be executed on the server" {
        BeforeAll {
            if ($skipTest) { return }

            Invoke-Command -Session $session -ScriptBlock {
                function MyInitializerFunction { param($x = $PID) $x }
            }

            $localPid = $PID
            $remotePid = Invoke-Command $session { $PID }

            # Sanity check
            $localPid | Should Not Be $remotePid

            $module = Import-PSSession -Session $session -Name MyInitializerFunction -AllowClobber
        }

        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Initializer run on the remote server" -Skip:$skipTest {
            (MyInitializerFunction) | Should Be $remotePid
        }

        It "Initializer not run when value provided" -Skip:$skipTest {
            (MyInitializerFunction 123) | Should Be 123
        }
    }

    Context "client-side parameters - cmdlet case" {
        BeforeAll {
            if ($skipTest) { return }
            $remotePid = Invoke-Command $session { $PID }
            $module = Import-PSSession -Session $session -Name Get-Variable -Type cmdlet -AllowClobber
        }

        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Importing by name/type should work" -Skip:$skipTest {
            (Get-Variable -Name PID).Value | Should Not Be $PID
        }

        It "Test -AsJob parameter" -Skip:$skipTest {
            try {
                $job = Get-Variable -Name PID -AsJob

                $job | Should Not Be NullOrEmpty
                ($job -is [System.Management.Automation.Job]) | Should Be $true
                ($job.Finished.WaitOne([TimeSpan]::FromSeconds(10), $false)) | Should Be $true
                $job.JobStateInfo.State | Should Be 'Completed'

                $childJob = $job.ChildJobs[0]
                $childJob.Output.Count | Should Be 1
                $childJob.Output[0].Value | Should Be $remotePid
            } finally {
                Remove-Job $job -Force
            }
        }

        It "Test OutVariable" -Skip:$skipTest {
            $result1 = Get-Variable -Name PID -OutVariable global:result2
            $result1.Value | Should Be $remotePid
            $global:result2[0].Value | Should Be $remotePid
        }
    }

    Context "client-side parameters - Windows 7 bug #759434" {
        BeforeAll {
            if ($skipTest) { return }
            $module = Import-PSSession -Session $session -Name Write-Warning -Type cmdlet -Prefix Remote -AllowClobber
        }

        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Test warnings present with '-WarningAction Continue'" -Skip:$skipTest {
            try {
                $jobWithWarnings = write-remotewarning foo -WarningAction continue -Asjob
                $null = Wait-Job $jobWithWarnings

                $jobWithWarnings.ChildJobs[0].Warning.Count | Should Be 1
            } finally {
                Remove-Job $jobWithWarnings -Force
            }
        }

        It "Test no warnings with '-WarningAction SilentlyContinue'" -Skip:$skipTest {
            try {
                $jobWithoutWarnings = write-remotewarning foo -WarningAction silentlycontinue -Asjob
                $null = Wait-Job $jobWithoutWarnings

                $jobWithoutWarnings.ChildJobs[0].Warning.Count | Should Be 0
            } finally {
                Remove-Job $jobWithoutWarnings -Force
            }
        }
    }

    Context "client-side parameters - non-cmdlet case" {
        BeforeAll {
            if ($skipTest) { return }

            Invoke-Command $session { function foo { param($OutVariable) "OutVariable = $OutVariable" } }

            # Sanity check
            Invoke-Command $session { foo -OutVariable x } | Should Be "OutVariable = x"

            $module = Import-PSSession -Session $session -Name foo -Type function -AllowClobber
        }

        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Implicit remoting: OutVariable is not intercepted for non-cmdlet-bound functions" -Skip:$skipTest {
            foo -OutVariable x | Should Be "OutVariable = x"
        }
    }

    Context "switch and positional parameters" {
        BeforeAll {
            if ($skipTest) { return }
            $remotePid = Invoke-Command $session { $PID }
            $module = Import-PSSession -Session $session -Name Get-Variable -Type cmdlet -Prefix Remote -AllowClobber
        }

        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Switch parameters work fine" -Skip:$skipTest {
            $proxiedPid = Get-RemoteVariable -Name pid -ValueOnly
            $remotePid | Should Be $proxiedPid
        }

        It "Positional parameters work fine" -Skip:$skipTest {
            $proxiedPid = Get-RemoteVariable pid
            $remotePid | Should Be ($proxiedPid.Value)
        }
    }
}

Describe "Implicit remoting on restricted ISS" -tags "Feature" {

    BeforeAll {
        # Skip tests for CoreCLR for now
        # Skip tests on ARM
        $skipTest = $IsCoreCLR -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM'

        if ($skipTest) { return }

        $sessionConfigurationDll = [IO.Path]::Combine([IO.Path]::GetTempPath(), "ImplicitRemotingRestrictedConfiguration$(Get-Random).dll")
        Add-Type -OutputAssembly $sessionConfigurationDll -TypeDefinition @"

        using System;
        using System.Collections.Generic;
        using System.Management.Automation;
        using System.Management.Automation.Runspaces;
        using System.Management.Automation.Remoting;

        namespace MySessionConfiguration
        {
            public class MySessionConfiguration : PSSessionConfiguration
            {
                public override InitialSessionState GetInitialSessionState(PSSenderInfo senderInfo)
                {
                    //System.Diagnostics.Debugger.Launch();
                    //System.Diagnostics.Debugger.Break();

                    InitialSessionState iss = InitialSessionState.CreateRestricted(System.Management.Automation.SessionCapabilities.RemoteServer);

                    // add Out-String for testing stuff
                    iss.Commands["Out-String"][0].Visibility = SessionStateEntryVisibility.Public;

                    // remove all commands that are not public
                    List<string> commandsToRemove = new List<string>();
                    foreach (SessionStateCommandEntry entry in iss.Commands)
                    {
                        List<SessionStateCommandEntry> sameNameEntries = new List<SessionStateCommandEntry>(iss.Commands[entry.Name]);
                        if (!sameNameEntries.Exists(delegate(SessionStateCommandEntry e) { return e.Visibility == SessionStateEntryVisibility.Public; }))
                        {
                            commandsToRemove.Add(entry.Name);
                        }
                    }

                    foreach (string commandToRemove in commandsToRemove)
                    {
                        iss.Commands.Remove(commandToRemove, null /* all types */);
                    }

                    return iss;
                }
            }
        }
"@

        Get-PSSessionConfiguration ImplicitRemotingRestrictedConfiguration* | Unregister-PSSessionConfiguration -Force

        ## The 'Register-PSSessionConfiguration' call below raises an AssemblyLoadException in powershell core:
        ## "Could not load file or assembly 'Microsoft.Powershell.Workflow.ServiceCore, Version=3.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35'. The system cannot find the file specified."
        ## Issue #2555 is created to track this issue and all tests here are skipped for CoreCLR for now.

        $myConfiguration = Register-PSSessionConfiguration `
            -Name ImplicitRemotingRestrictedConfiguration `
            -ApplicationBase (Split-Path $sessionConfigurationDll) `
            -AssemblyName (Split-Path $sessionConfigurationDll -Leaf) `
            -ConfigurationTypeName "MySessionConfiguration.MySessionConfiguration" `
            -Force

        $session = New-RemoteSession -ConfigurationName $myConfiguration.Name
        $session | Should Not Be $null
    }

    AfterAll {
        if ($skipTest) { return }
        if ($null -ne $session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
        if ($null -ne $myConfiguration) { Unregister-PSSessionConfiguration -Name ($myConfiguration.Name) -Force -ErrorAction SilentlyContinue }
        if ($null -ne $sessionConfigurationDll) { Remove-Item $sessionConfigurationDll -Force -ErrorAction SilentlyContinue }
    }

    Context "restrictions works" {
        It "Get-Variable is private" -Skip:$skipTest {
            @(Invoke-Command $session { Get-Command -Name Get-Variabl* }).Count | Should Be 0
        }
        It "Only 9 commands are public" -Skip:$skipTest {
            @(Invoke-Command $session { Get-Command }).Count | Should Be 9
        }
    }

    Context "basic functionality of Import-PSSession works (against a directly exposed cmdlet and against a proxy function)" {
        BeforeAll {
            if ($skipTest) { return }
            $module = Import-PSSession $session Out-Strin*,Measure-Object -Type Cmdlet,Function -ArgumentList 123 -AllowClobber
        }
        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "Import-PSSession works against the ISS-restricted runspace (Out-String)" -Skip:$skipTest {
            @(Get-Command Out-String -Type Function).Count | Should Be 1
        }

        It "Import-PSSession works against the ISS-restricted runspace (Measure-Object)" -Skip:$skipTest {
            @(Get-Command Measure-Object -Type Function).Count | Should Be 1
        }

        It "Invoking an implicit remoting proxy works against the ISS-restricted runspace (Out-String)" -Skip:$skipTest {
            $remoteResult = Out-String -input ("blah " * 10) -Width 10
            $localResult = Microsoft.PowerShell.Utility\Out-String -input ("blah " * 10) -Width 10

            $localResult | Should Be $remoteResult
        }

        It "Invoking an implicit remoting proxy works against the ISS-restricted runspace (Measure-Object)" -Skip:$skipTest {
            $remoteResult = 1..10 | Measure-Object
            $localResult = 1..10 | Microsoft.PowerShell.Utility\Measure-Object
            ($localResult.Count) | Should Be ($remoteResult.Count)
        }
    }
}

Describe "Implicit remoting tests" -tags "Feature" {

    BeforeAll {
        # Skip test for non-windows machines for now
        $skipTest = !$IsWindows

        if ($skipTest) { return }

        $session = New-RemoteSession
    }

    AfterAll {
        if ($skipTest) { return }
        if ($null -ne $session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
    }

    Context "Get-Command <Imported-Module> and <Imported-Module.Name> work (Windows 7: #334112)" {
        BeforeAll {
            if ($skipTest) { return }
            $module = Import-PSSession $session Get-Variable -Prefix My -AllowClobber
        }
        AfterAll {
            if ($skipTest) { return }
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        It "PSModuleInfo.Name shouldn't contain a psd1 extension" -Skip:$skipTest {
            ($module.Name -notlike '*.psd1') | Should Be $true
        }

        It "PSModuleInfo.Name shouldn't contain a psm1 extension" -Skip:$skipTest {
            ($module.Name -notlike '*.psm1') | Should Be $true
        }

        It "PSModuleInfo.Name shouldn't contain a path" -Skip:$skipTest {
            ($module.Name -notlike "${env:TMP}*") | Should Be $true
        }

        It "Get-Command returns only 1 public command from implicit remoting module (1)" -Skip:$skipTest {
            $c = @(Get-Command -Module $module)
            $c.Count | Should Be 1
            $c[0].Name | Should Be "Get-MyVariable"
        }

        It "Get-Command returns only 1 public command from implicit remoting module (2)" -Skip:$skipTest {
            $c = @(Get-Command -Module $module.Name)
            $c.Count | Should Be 1
            $c[0].Name | Should Be "Get-MyVariable"
        }
    }

    Context "progress bar should be 1) present and 2) completed also" {
        BeforeAll {
            if ($skipTest) { return }

            $file = [IO.Path]::Combine([IO.Path]::GetTempPath(), [Guid]::NewGuid().ToString())
            $powerShell = [PowerShell]::Create().AddCommand("Export-PSSession").AddParameter("Session", $session).AddParameter("ModuleName", $file).AddParameter("CommandName", "Get-Process").AddParameter("AllowClobber")
            $powerShell.Invoke() | Out-Null
        }
        AfterAll {
            if ($skipTest) { return }
            $powerShell.Dispose()
            if ($null -ne $file) { Remove-Item $file -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It "'Completed' progress record should be present" -Skip:$skipTest {
            ($powerShell.Streams.Progress | Select-Object -last 1).RecordType.ToString() | Should Be "Completed"
        }
    }

    Context "display of property-less objects (not sure if this test belongs here) (Windows 7: #248499)" {
        BeforeAll {
            if ($skipTest) { return }
            $x = new-object random
	        $expected = $x.ToString()
        }

        # Since New-PSSession now only loads Microsoft.PowerShell.Core and for the session in the test, Autoloading is disabled, engine cannot find New-Object as it is part of Microsoft.PowerShell.Utility module.
        # The fix is to import this module before running the command.
        It "Display of local property-less objects" -Skip:$skipTest {
            ($x | Out-String).Trim() | Should Be $expected
        }
        It "Display of remote property-less objects" -Skip:$skipTest {
            (Invoke-Command $session { Import-Module Microsoft.PowerShell.Utility; New-Object random } | out-string).Trim() | Should Be $expected
        }
    }

    It "piping between remoting proxies should work" -Skip:$skipTest {
        try {
            $module = Import-PSSession -Session $session -Name Write-Output -AllowClobber
            $result = Write-Output 123 | Write-Output
            $result | Should Be 123
        } finally {
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }
    }

    It "Strange parameter names should trigger an error" -Skip:$skipTest {
        try {
            Invoke-Command $session { function attack(${foo="$(calc)"}){echo "It is done."}}
            $module = Import-PSSession -Session $session -CommandName attack -ErrorAction SilentlyContinue -ErrorVariable expectedError -AllowClobber
            $expectedError | Should Not Be NullOrEmpty
        } finally {
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }
    }

    It "Non-terminating error from remote end got duplicated locally" -Skip:$skipTest {
        try {
            Invoke-Command $session { $oldGetCommand = ${function:Get-Command} }
            Invoke-Command $session { function Get-Command { write-error blah } }
            $module = Import-PSSession -Session $session -ErrorAction SilentlyContinue -ErrorVariable expectedError -AllowClobber

            $expectedError | Should Not Be NullOrEmpty

            $msg = [string]($expectedError[0])
            $msg.Contains("blah") | Should Be $true
        } finally {
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
            Invoke-Command $session { ${function:Get-Command} = $oldGetCommand }
        }
    }

    It "Should get an error if remote server returns something that wasn't asked for" -Skip:$skipTest {
        try {
            Invoke-Command $session { $oldGetCommand = ${function:Get-Command} }
            Invoke-Command $session { function notRequested { "notRequested" }; function Get-Command { Microsoft.PowerShell.Core\Get-Command Get-Variable,notRequested } }
            $module = Import-PSSession -Session $session Get-Variable -AllowClobber -ErrorAction SilentlyContinue -ErrorVariable expectedError

            $expectedError | Should Not Be NullOrEmpty

            $msg = [string]($expectedError[0])
            $msg.Contains("notRequested") | Should Be $true
        } finally {
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
            Invoke-Command $session { ${function:Get-Command} = $oldGetCommand }
        }
    }

    It "Get-Command returns something that is not CommandInfo" -Skip:$skipTest {
        try {
            Invoke-Command $session { $oldGetCommand = ${function:Get-Command} }
            Invoke-Command $session { function Get-Command { Microsoft.PowerShell.Utility\Get-Variable } }

            $module = Import-PSSession -Session $session -AllowClobber
            throw "Import-PSSession should throw"
        } catch {
            $msg = [string]($_)
            $msg.Contains("Get-Command") | Should Be $true
        } finally {
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
            Invoke-Command $session { ${function:Get-Command} = $oldGetCommand }
        }
    }

    # Test order of remote commands (alias > function > cmdlet > external script)
    It "Command resolution for 'myOrder' should be respected by implicit remoting" -Skip:$skipTest {
        try
        {
            $tempdir = Join-Path $env:TEMP ([IO.Path]::GetRandomFileName())
            $null = New-Item $tempdir -ItemType Directory -Force
            $oldPath = Invoke-Command $session { $env:PATH }

            'param([Parameter(Mandatory=$true)]$scriptParam) "external script / $scriptParam"' > $tempdir\myOrder.ps1
            Invoke-Command $session { param($x) $env:PATH = $env:PATH + [IO.Path]::PathSeparator + $x } -ArgumentList $tempDir
            Invoke-Command $session { function myOrder { param([Parameter(Mandatory=$true)]$functionParam) "function / $functionParam" } }
            Invoke-Command $session { function helper { param([Parameter(Mandatory=$true)]$aliasParam) "alias / $aliasParam" }; Set-Alias myOrder helper }

            $expectedResult = Invoke-Command $session { myOrder -aliasParam 123 }

            $module = Import-PSSession $session myOrder -CommandType All -AllowClobber
            $actualResult = myOrder -aliasParam 123

            $expectedResult | Should Be $actualResult
        } finally {
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
            Invoke-Command $session { param($x) $env:PATH = $x; Remove-Item Alias:\myOrder, Function:\myOrder, Function:\helper -Force -ErrorAction SilentlyContinue } -ArgumentList $oldPath
            Remove-Item $tempDir -Force -Recurse -ErrorAction SilentlyContinue
        }
    }

    It "Test -Prefix parameter" -Skip:$skipTest {
        try {
            $module = Import-PSSession -Session $session -Name Get-Variable -Type cmdlet -Prefix My -AllowClobber
            (Get-MyVariable -Name pid).Value | Should Not Be $PID
        } finally {
            if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        }

        (Get-Item function:Get-MyVariable -ErrorAction SilentlyContinue) | Should Be $null
    }

    Context "BadVerbs of functions should trigger a warning" {
        BeforeAll {
            if ($skipTest) { return }
            Invoke-Command $session { function BadVerb-Variable { param($name) Get-Variable $name } }
        }
        AfterAll {
            if ($skipTest) { return }
            Invoke-Command $session { Remove-Item Function:\BadVerb-Variable }
        }

        It "Bad verb causes no error but warning" -Skip:$skipTest {
            try {
                $ps = [powershell]::Create().AddCommand("Import-PSSession", $true).AddParameter("Session", $session).AddParameter("CommandName", "BadVerb-Variable")
                $module = $ps.Invoke() | Select-Object -First 1

                $ps.Streams.Error.Count | Should Be 0
                $ps.Streams.Warning.Count | Should Not Be 0
            } finally {
                if ($null -ne $module) {
                    $ps.Commands.Clear()
                    $ps.AddCommand("Remove-Module").AddParameter("ModuleInfo", $module).AddParameter("Force", $true) > $null
                    $ps.Invoke() > $null
                }
                $ps.Dispose()
            }
        }

        It "Imported function with bad verb should work" -Skip:$skipTest {
            try {
                $module = Import-PSSession $session BadVerb-Variable -WarningAction SilentlyContinue -AllowClobber

                $remotePid = Invoke-Command $session { $PID }
                $getVariablePid = Invoke-Command $session { (Get-Variable -Name PID).Value }
                $getVariablePid | Should Be $remotePid

                ## Get-Variable function should not be exported when importing a BadVerb-Variable function
                Get-Item Function:\Get-Variable -ErrorAction SilentlyContinue | Should Be $null

                ## BadVerb-Variable should be a function, not an alias (1)
                Get-Item Function:\BadVerb-Variable -ErrorAction SilentlyContinue | Should Not Be $null

                ## BadVerb-Variable should be a function, not an alias (2)
                Get-Item Alias:\BadVerb-Variable -ErrorAction SilentlyContinue | Should Be $null

                (BadVerb-Variable -Name pid).Value | Should Be $remotePid
            } finally {
                if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
            }
        }

        It "Test warning is supressed by '-DisableNameChecking'" -Skip:$skipTest {
            try {
                $ps = [powershell]::Create().AddCommand("Import-PSSession", $true).AddParameter("Session", $session).AddParameter("CommandName", "BadVerb-Variable").AddParameter("DisableNameChecking", $true)
                $module = $ps.Invoke() | Select-Object -First 1

                $ps.Streams.Error.Count | Should Be 0
                $ps.Streams.Warning.Count | Should Be 0
            } finally {
                if ($null -ne $module) {
                    $ps.Commands.Clear()
                    $ps.AddCommand("Remove-Module").AddParameter("ModuleInfo", $module).AddParameter("Force", $true) > $null
                    $ps.Invoke() > $null
                }
                $ps.Dispose()
            }
        }

        It "Imported function with bad verb by 'Import-PSSession -DisableNameChecking' should work" -Skip:$skipTest {
            try {
                $module = Import-PSSession $session BadVerb-Variable -DisableNameChecking -AllowClobber

                $remotePid = Invoke-Command $session { $PID }
                $getVariablePid = Invoke-Command $session { (Get-Variable -Name PID).Value }
                $getVariablePid | Should Be $remotePid

                ## Get-Variable function should not be exported when importing a BadVerb-Variable function
                Get-Item Function:\Get-Variable -ErrorAction SilentlyContinue | Should Be $null

                ## BadVerb-Variable should be a function, not an alias (1)
                Get-Item Function:\BadVerb-Variable -ErrorAction SilentlyContinue | Should Not Be $null

                ## BadVerb-Variable should be a function, not an alias (2)
                Get-Item Alias:\BadVerb-Variable -ErrorAction SilentlyContinue | Should Be $null

                (BadVerb-Variable -Name pid).Value | Should Be $remotePid
            } finally {
                if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
            }
        }
    }

    Context "BadVerbs of alias shouldn't trigger a warning + can import an alias without saying -CommandType Alias" {
        BeforeAll {
            if ($skipTest) { return }
            Invoke-Command $session { Set-Alias BadVerb-Variable Get-Variable }
        }
        AfterAll {
            if ($skipTest) { return }
            Invoke-Command $session { Remove-Item Alias:\BadVerb-Variable }
        }

        It "Bad verb alias causes no error or warning" -Skip:$skipTest {
            try {
                $ps = [powershell]::Create().AddCommand("Import-PSSession", $true).AddParameter("Session", $session).AddParameter("CommandName", "BadVerb-Variable")
                $module = $ps.Invoke() | Select-Object -First 1

                $ps.Streams.Error.Count | Should Be 0
                $ps.Streams.Warning.Count | Should Be 0
            } finally {
                if ($null -ne $module) {
                    $ps.Commands.Clear()
                    $ps.AddCommand("Remove-Module").AddParameter("ModuleInfo", $module).AddParameter("Force", $true) > $null
                    $ps.Invoke() > $null
                }
                $ps.Dispose()
            }
        }

        It "Importing alias with bad verb should work" -Skip:$skipTest {
            try {
                $module = Import-PSSession $session BadVerb-Variable -AllowClobber

                $remotePid = Invoke-Command $session { $PID }
                $getVariablePid = Invoke-Command $session { (Get-Variable -Name PID).Value }
                $getVariablePid | Should Be $remotePid

                ## BadVerb-Variable should be an alias, not a function (1)
                Get-Item Function:\BadVerb-Variable -ErrorAction SilentlyContinue | Should Be $null

                ## BadVerb-Variable should be an alias, not a function (2)
                Get-Item Alias:\BadVerb-Variable -ErrorAction SilentlyContinue | Should Not Be $null

                (BadVerb-Variable -Name pid).Value | Should Be $remotePid
            } finally {
                if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
            }
        }
    }

    It "Removing a module should clean-up event handlers (Windows 7: #268819)" -Skip:$skipTest {
        $oldNumberOfHandlers = $executionContext.GetType().GetProperty("Events").GetValue($executionContext, $null).Subscribers.Count
        $module = Import-PSSession -Session $session -Name Get-Random -AllowClobber

        Remove-Module $module -Force
        $newNumberOfHandlers = $executionContext.GetType().GetProperty("Events").GetValue($executionContext, $null).Subscribers.Count

        ## Event should be unregistered when the module is removed
        $oldNumberOfHandlers | Should Be $newNumberOfHandlers

        ## Private functions from the implicit remoting module shouldn't get imported into global scope
        @(dir function:*Implicit* -ErrorAction SilentlyContinue).Count | Should Be 0
    }
}

Describe "Export-PSSession function" -tags "Feature" {
    BeforeAll {
        # Skip test for non-windows machines for now
        $skipTest = !$IsWindows

        if ($skipTest) { return }

        $session = New-RemoteSession

        $tempdir = Join-Path $env:TEMP ([IO.Path]::GetRandomFileName())
        New-Item $tempdir -ItemType Directory > $null

        @"
        Import-Module `"$tempdir\Diag`"
        `$mod = Get-Module Diag
        Return `$mod
"@ > $tempdir\TestBug450687.ps1
    }

    AfterAll {
        if ($skipTest) { return }
        if ($null -ne $session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
        if ($null -ne $tempdir) { Remove-Item $tempdir -Force -Recurse -ErrorAction SilentlyContinue }
    }

    It "Test the module created by Export-PSSession" -Skip:$skipTest {
        try {
            Export-PSSession -Session $session -OutputModule $tempdir\Diag -CommandName New-Guid -AllowClobber > $null

            # Only the snapin Microsoft.PowerShell.Core is loaded
            $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
            $ps = [PowerShell]::Create($iss)
            $result = $ps.AddScript(" & $tempdir\TestBug450687.ps1").Invoke()

            ## The module created by Export-PSSession is imported successfully
            ($null -ne $result -and $result.Count -eq 1 -and $result[0].Name -eq "Diag") | Should Be $true

            ## The command Add-BitsFile is imported successfully
            $c = $result[0].ExportedCommands["New-Guid"]
            ($null -ne $c -and $c.CommandType -eq "Function") | Should Be $true
        } finally {
            $ps.Dispose()
        }
    }
}

Describe "Implicit remoting with disconnected session" -tags "Feature" {
    BeforeAll {
        # Skip test for non-windows machines for now
        $skipTest = !$IsWindows

        if ($skipTest) { return }

        $session = New-RemoteSession -Name Session102
        $remotePid = Invoke-Command $session { $PID }
        $module = Import-PSSession $session Get-Variable -prefix Remote -AllowClobber
    }

    AfterAll {
        if ($skipTest) { return }
        if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        if ($null -ne $session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
    }

    It "Remote session PID should be different" -Skip:$skipTest {
        $sessionPid = Get-RemoteVariable pid
        $sessionPid.Value | Should Be $remotePid
    }

    It "Disconnected session should be reconnected when calling proxied command" -Skip:$skipTest {
        Disconnect-PSSession $session

        $dSessionPid = Get-RemoteVariable pid
        $dSessionPid.Value | Should Be $remotePid

        $session.State | Should Be 'Opened'
    }

    ## It requires 'New-PSSession' to work with implicit credential to allow proxied command to create new session.
    ## Implicit credential doesn't work in AppVeyor builder, so mark this test '-pending'.
    It "Should have a new session when the disconnected session cannot be re-connected" -Pending {
        ## Disconnect session and make it un-connectable.
        Disconnect-PSSession $session
        start powershell -arg 'Get-PSSession -cn localhost -name Session102 | Connect-PSSession' -Wait

        sleep 3

        ## This time a new session is created because the old one is unavailable.
        $dSessionPid = Get-RemoteVariable pid
        $dSessionPid.Value | Should Not Be $remotePid
    }
}

Describe "Select-Object with implicit remoting" -tags "Feature" {
    BeforeAll {
        # Skip test for non-windows machines for now
        $skipTest = !$IsWindows

        if ($skipTest) { return }

        $session = New-RemoteSession
        Invoke-Command $session { function foo { "a","b","c" } }
        $module = Import-PSSession $session foo -AllowClobber
    }

    AfterAll {
        if ($skipTest) { return }
        if ($null -ne $module) { Remove-Module $module -Force -ErrorAction SilentlyContinue }
        if ($null -ne $session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
    }

    It "Select -First should work with implicit remoting" -Skip:$skipTest {
        $bar = foo | Select-Object -First 2
        $bar | Should Not Be NullOrEmpty
        $bar.Count | Should Be 2
        $bar[0] | Should Be "a"
        $bar[1] | Should Be "b"
    }
}

Describe "Get-FormatData used in Export-PSSession should work on DL targets" -tags "Feature" {
    BeforeAll {
        # Skip tests for CoreCLR for now
        # Skip tests if .NET 2.0 and PS 2.0 is installed on the machine
        $skipTest = $IsCoreCLR -or (! (Test-Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v2.0.50727')) -or
                                   (! (Test-Path 'HKLM:\SOFTWARE\Microsoft\PowerShell\1\PowerShellEngine'))

        if ($skipTest) { return }

        ## The call to 'Register-PSSessionConfiguration -PSVersion 2.0' below raises and exception:
        ## `Cannot bind parameter 'PSVersion' to the target. Exception setting "PSVersion": "Windows PowerShell 2.0 is not installed.
        ##  Install Windows PowerShell 2.0, and then try again."`
        ## Issue #2556 is created to track this issue and the test here is skipped for CoreCLR for now.

        $configName = "DLConfigTest"
        $null = Register-PSSessionConfiguration -Name $configName -PSVersion 2.0 -Force
        $session = New-RemoteSession -ConfigurationName $configName
    }

    AfterAll {
        if ($skipTest) { return }
        if ($null -ne $session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
        Unregister-PSSessionConfiguration -Name $configName -Force -ErrorAction SilentlyContinue
    }

    It "Verifies that Export-PSSession with PS 2.0 session and format type names succeeds" -Skip:$skipTest {
        try {
            $results = Export-PSSession -Session $session -OutputModule tempTest -CommandName Get-Process `
                                        -AllowClobber -FormatTypeName * -Force -ErrorAction Stop
            $results.Count | Should Not Be 0
        } finally {
            if ($results.Count -gt 0) {
                Remove-Item -Path $results[0].DirectoryName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe "GetCommand locally and remotely" -tags "Feature" {

    BeforeAll {
        # Run this test only on FullCLR powershell
        $skipTest = !$IsWindows -or $IsCoreCLR

        if ($skipTest) { return }
        $session = New-RemoteSession
    }

    AfterAll {
        if ($skipTest) { return }
        if ($null -ne $session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
    }

    It "Verifies that the number of local cmdlet command count is the same as remote cmdlet command count." -Skip:$skipTest {
        $localCommandCount = (Get-Command -Type Cmdlet).Count
        $remoteCommandCount = Invoke-Command { (Get-Command -Type Cmdlet).Count }
        $localCommandCount | Should Be $remoteCommandCount
    }
}

Describe "Import-PSSession on Restricted Session" -tags "Feature","RequireAdminOnWindows","Slow" {

    BeforeAll {

        # Skip tests for non Windows
        if (! $IsWindows)
        {
            $originalDefaultParameters = $PSDefaultParameterValues.Clone()
            $global:PSDefaultParameterValues["it:skip"] = $true
        }
        else
        {
            New-PSSessionConfigurationFile -Path $TestDrive\restricted.pssc -SessionType RestrictedRemoteServer
            Register-PSSessionConfiguration -Path $TestDrive\restricted.pssc -Name restricted -Force
            $session = New-PSSession -ComputerName localhost -ConfigurationName restricted
        }
    }

    AfterAll {

        if ($originalDefaultParameters -ne $null)
        {
            $global:PSDefaultParameterValues = $originalDefaultParameters
        }
        else
        {
            if ($session -ne $null) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
            Unregister-PSSessionConfiguration -Name restricted -Force -ErrorAction SilentlyContinue
        }
    }

    # Blocked by https://github.com/PowerShell/PowerShell/issues/4275
    # Need a way to created restricted endpoint based on a different endpoint other than microsoft.powershell which points
    # to Windows PowerShell 5.1
    It "Verifies that Import-PSSession works on a restricted session" -Pending {

        $errorVariable = $null
        Import-PSSession -Session $session -AllowClobber -ErrorVariable $errorVariable
        $errorVariable | Should BeNullOrEmpty
    }
}
