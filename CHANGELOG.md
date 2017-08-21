# Changelog

## v6.0.0-beta.5 - 2017-08-02

### Breaking changes

* Remove the `*-Counter` cmdlets in `Microsoft.PowerShell.Diagnostics` due to the use of unsupported APIs until a better solution is found. (#4303)
* Remove the `Microsoft.PowerShell.LocalAccounts` due to the use of unsupported APIs until a better solution is found. (#4302)

### Engine updates and fixes

* Fix the issue where PowerShell Core wasn't working on Windows 7 or Windows Server 2008 R2/2012 (non-R2). (#4463)
* `ValidateSetAttribute` enhancement: support set values to be dynamically generated from a custom `ValidateSetValueGenerator`. (#3784) (Thanks to @iSazonov!)
* Disable breaking into debugger on Ctrl+Break when running non-interactively. (#4283) (Thanks to @mwrock!)
* Give error instead of crashing if WSMan client library is not available. (#4387)
* Allow passing `$true`/`$false` as a parameter to scripts using `powershell.exe -File`. (#4178)
* Enable `DataRow`/`DataRowView` adapters in PowerShell Core to fix an issue with `DataTable` usage. (#4258)
* Fix an issue where PowerShell class static methods were being shared across `Runspace`s/`SessionState`s. (#4209)
* Fix array expression to not return null or throw error. (#4296)
* Fixes a CIM deserialization bug where corrupted CIM classes were instantiating non-CIM types. (#4234)
* Improve error message when `HelpMessage` property of `ParameterAttribute` is set to empty string. (#4334)
* Make `ShellExecuteEx` run in a STA thread. (#4362)

### General cmdlet updates and fixes

* Add `-SkipHeaderValidation` switch to `Invoke-WebRequest` and `Invoke-RestMethod` to support adding headers without validating the header value. (#4085)
* Add support for `Invoke-Item -Path <folder>`. (#4262)
* Fix `ConvertTo-Html` output when using a single column header. (#4276)
* Fix output of `Length` for `FileInfo` when using `Format-List`. (#4437)
* Fix an issue in implicit remoting where restricted sessions couldn't use `Get-FormatData –PowerShellVersion`. (#4222)
* Fix an issue where `Register-PSSessionConfiguration` fails if `SessionConfig` folder doesn't exist. (#4271)

### Installer updates

* Create script to install latest PowerShell from Microsoft package repositories (or Homebrew) on non-Windows platforms. (#3608) (Thanks to @DarwinJS!)
* Enable MSI upgrades rather than a side-by-side install. (#4259)
* Add a checkbox to open PowerShell after the Windows MSI installer has finished. (#4203) (Thanks to @bergmeister!)
* Add Amazon Linux compatibility to `install-powershell.sh`. (#4360) (Thanks to @DarwinJS!)
* Add ability to package PowerShell Core as a NuGet package. (#4363)

### Build/test and code cleanup

* Add build check for MFC for Visual C++ during Windows builds.
  This fixes a long-standing (and very frustrating!) issue with missing build dependencies! (#4185) (Thanks to @KirkMunro!)
* Move building Windows PSRP binary out of `Start-PSBuild`.
  Now `Start-PSBuild` doesn't build PSRP binary on windows. Instead, we consume the PSRP binary from a NuGet package. (#4335)
* Add tests for built-in type accelerators. (#4230) (Thanks to @dchristian3188!)
* Increase code coverage of `Get-ChildItem` on file system. (#4342) (Thanks to @jeffbi!)
* Increase test coverage for `Rename-Item` and `Move-Item`. (#4329) (Thanks to @jeffbi!)
* Add test coverage for Registry provider. (#4354) (Thanks to @jeffbi!)
* Fix warnings and errors thrown by PSScriptAnalyzer. (#4261) (Thanks to @bergmeister!)
* Fix regressions that cause implicit remoting tests to fail. (#4326)
* Disable legacy UTC and SQM Windows telemetry by enclosing the code in '#if LEGACYTELEMETRY'. (#4190)

### Cleanup `#if CORECLR` code

PowerShell 6.0 will be exclusively built on top of CoreCLR,
so we are removing a large amount of code that's built only for FullCLR.
To read more about this, check out [this blog post](https://blogs.msdn.microsoft.com/powershell/2017/07/14/powershell-6-0-roadmap-coreclr-backwards-compatibility-and-more/).

## v6.0.0-beta.4 - 2017-07-12

## Windows PowerShell backwards compatibility

In the `beta.4` release, we've introduced a change to add the Windows PowerShell `PSModulePath` to the default `PSModulePath` in PowerShell Core on Windows. (#4132)

Along with the introduction of .NET Standard 2.0 in `6.0.0-beta.1` and a GAC probing fix in `6.0.0-beta.3`,
**this change will enable a large number of your existing Windows PowerShell modules/scripts to "just work" inside of PowerShell Core on Windows**.
(Note: We have also fixed the CDXML modules on Windows that were regressed in `6.0.0-beta.2` as part of #4144).

So that we can further enable this backwards compatibility,
we ask that you tell us more about what modules or scripts do and don't work in Issue #4062.
This feedback will also help us determine if `PSModulePath` should include the Windows PowerShell values by default in the long run.

For more information on this, we invite you to read [this blog post explaining PowerShell Core and .NET Standard in more detail](https://blogs.msdn.microsoft.com/powershell/?p=13355).

### Engine updates and fixes

- Add Windows PowerShell `PSModulePath` by default on Windows. (#4132)
- Move PowerShell to `2.0.0-preview3-25426-01` and using the .NET CLI version `2.0.0-preview2-006502`. (#4144)
- Performance improvement in PSReadline by minimizing writing ANSI escape sequences. (#4110)
- Implement Unicode escape parsing so that users can use Unicode characters as arguments, strings or variable names. (#3958) (Thanks to @rkeithhill!)
- Script names or full paths can have commas. (#4136) (Thanks to @TimCurwick!)
- Added `semver` as a type accelerator for `System.Management.Automation.SemanticVersion`. (#4142) (Thanks to @oising!)
- Close `eventLogSession` and `EventLogReader` to unlock an ETL log. (#4034) (Thanks to @iSazonov!)

### General cmdlet updates and fixes

- `Move-Item` cmdlet honors `-Include`, `-Exclude`, and `-Filter` parameters. (#3878)
- Add a parameter to `Get-ChildItem` called `-FollowSymlink` that traverses symlinks on demand, with checks for link loops. (#4020)
- Change `New-ModuleManifest` encoding to UTF8NoBOM on non-Windows platforms. (#3940)
- `Get-AuthenticodeSignature` cmdlets can now get file signature timestamp. (#4061)
- Add tab completion for `Export-Counter` `-FileFormat` parameter. (#3856)
- Fixed `Import-Module` on non-Windows platforms so that users can import modules with `NestedModules` and `RootModules`. (#4010)
- Close `FileStream` opened by `Get-FileHash`. (#4175) (Thanks to @rkeithhill!)

### Remoting

- Fixed hang when the SSH client abruptly terminates. (#4123)

### Documentation

- Added recommended settings for VS Code. (#4054) (Thanks to @iSazonov!)

## v6.0.0-beta.3 - 2017-06-20

### Breaking changes

- Remove the `BuildVersion` property from `$PSVersionTable`.
 This property was strongly tied to the Windows build version.
 Instead, we recommend that you use `GitCommitId` to retrieve the exact build version of PowerShell Core.
 (#3877) (Thanks to @iSazonov!)
- Change positional parameter for `powershell.exe` from `-Command` to `-File`.
 This fixes the usage of `#!` (aka as a shebang) in PowerShell scripts that are being executed from non-PowerShell shells on non-Windows platforms.
 This also means that you can now do things like `powershell foo.ps1` or `powershell fooScript` without specifying `-File`.
 However, this change now requires that you explicitly specify `-c` or `-Command` when trying to do things like `powershell.exe Get-Command`.
 (#4019)
- Remove `ClrVersion` property from `$PSVersionTable`.
 (This property is largely irrelevant for .NET Core,
 and was only preserved in .NET Core for specific legacy purposes that are inapplicable to PowerShell.)
 (#4027)

### Engine updates and fixes

- Add support to probe and load assemblies from GAC on Windows platform.
 This means that you can now load Windows PowerShell modules with assembly dependencies which reside in the GAC.
 If you're interested in running your traditional Windows PowerShell scripts and cmdlets using the power of .NET Standard 2.0,
 try adding your Windows PowerShell module directories to your PowerShell Core `$PSModulePath`.
 (E.g. `$env:PSModulePath += ';C:\Program Files\WindowsPowerShell\Modules;C:\WINDOWS\system32\WindowsPowerShell\v1.0\Modules'`)
 Even if the module isn't owned by the PowerShell Team, please tell us what works and what doesn't by leaving a comment in [issue #4062][issue-4062]! (#3981)
- Enhance type inference in tab completion based on runtime variable values. (#2744) (Thanks to @powercode!)
 This enables tab completion in situations like:
 ```powershell
 $p = Get-Process
 $p | Foreach-Object Prio<tab>
 ```
- Add `GitCommitId` to PowerShell Core banner.
 Now you don't have to run `$PSVersionTable` as soon as you start PowerShell to get the version! (#3916) (Thanks to @iSazonov!)
- Fix a bug in tab completion to make `native.exe --<tab>` call into native completer. (#3633) (Thanks to @powercode!)
- Fix PowerShell Core to allow use of long paths that are more than 260 characters. (#3960)
- Fix ConsoleHost to honour `NoEcho` on Unix platforms. (#3801)
- Fix transcription to not stop when a Runspace is closed during the transcription. (#3896)

[issue-4062]: https://github.com/PowerShell/PowerShell/issues/4062

### General cmdlet updates and fixes

- Enable `Send-MailMessage` in PowerShell Core. (#3869)
- Fix `Get-Help` to support case insensitive pattern matching on Unix platforms. (#3852)
- Fix tab completion on `Get-Help` for `about_*` topics. (#4014)
- Fix PSReadline to work in Windows Server Core container image. (#3937)
- Fix `Import-Module` to honour `ScriptsToProcess` when `-Version` is specified. (#3897)
- Strip authorization header on redirects with web cmdlets. (#3885)
- `Start-Sleep`: add the alias `ms` to the parameter `-Milliseconds`. (#4039) (Thanks to @Tadas!)

### Developer experience

- Make hosting PowerShell Core in your own .NET applications much easier by refactoring PowerShell Core to use the default CoreCLR loader. (#3903)
- Update `Add-Type` to support `CSharpVersion7`. (#3933) (Thanks to @iSazonov)

## v6.0.0-beta.2 - 2017-06-01

### Support backgrounding of pipelines with ampersand (`&`) (#3360)

- Putting `&` at the end of a pipeline will cause the pipeline to be run as a PowerShell job.
- When a pipeline is backgrounded, a job object is returned.
- Once the pipeline is running as a job, all of the standard `*-Job` cmdlets can be used to manage the job.
- Variables (ignoring process-specific variables) used in the pipeline are automatically copied to the job so `Copy-Item $foo $bar &` just works.
- The job is also run in the current directory instead of the user's home directory.
- For more information about PowerShell jobs, see [about_Jobs](https://msdn.microsoft.com/en-us/powershell/reference/6/about/about_jobs).

### Engine updates and fixes

- Crossgen more of the .NET Core assemblies to improve PowerShell Core startup time. (#3787)
- Enable comparison between a `SemanticVersion` instance and a `Version` instance that is constructed only with `Major` and `Minor` version values.
  This will fix some cases where PowerShell Core was failing to import older Windows PowerShell modules. (#3793) (Thanks to @mklement0!)

### General cmdlet updates and fixes

- Support Link header pagination in web cmdlets (#3828)
    - For `Invoke-WebRequest`, when the response includes a Link header we create a RelationLink property as a Dictionary representing the URLs and `rel` attributes and ensure the URLs are absolute to make it easier for the developer to use.
    - For `Invoke-RestMethod`, when the response includes a Link header we expose a `-FollowRelLink` switch to automatically follow `next` `rel` links until they no longer exist or once we hit the optional `-MaximumFollowRelLink` parameter value.
- Update `Get-ChildItem` to be more in line with the way that the *nix `ls -R` and the Windows `DIR /S` native commands handle symbolic links to directories during a recursive search.
  Now, `Get-ChildItem` returns the symbolic links it encountered during the search, but it won't search the directories those links target. (#3780)
- Fix `Get-ChildItem` to continue enumeration after throwing an error in the middle of a set of items.
  This fixes some issues where inaccessible directories or files would halt execution of `Get-ChildItem`. (#3806)
- Fix `ConvertFrom-Json` to deserialize an array of strings from the pipeline that together construct a complete JSON string.
  This fixes some cases where newlines would break JSON parsing. (#3823)
- Enable `Get-TimeZone` for macOS/Linux. (#3735)
- Change to not expose unsupported aliases and cmdlets on macOS/Linux. (#3595) (Thanks to @iSazonov!)
- Fix `Invoke-Item` to accept a file path that includes spaces on macOS/Linux. (#3850)
- Fix an issue where PSReadline was not rendering multi-line prompts correctly on macOS/Linux. (#3867)
- Fix an issue where PSReadline was not working on Nano Server. (#3815)

## v6.0.0-beta.1 - 2017-05-08

### Move to .NET Core 2.0 (.NET Standard 2.0 support)

PowerShell Core has moved to using .NET Core 2.0 so that we can leverage all the benefits of .NET Standard 2.0. (#3556)
To learn more about .NET Standard 2.0, there's some great starter content [on Youtube](https://www.youtube.com/playlist?list=PLRAdsfhKI4OWx321A_pr-7HhRNk7wOLLY),
on [the .NET blog](https://blogs.msdn.microsoft.com/dotnet/2016/09/26/introducing-net-standard/),
and [on GitHub](https://github.com/dotnet/standard/blob/master/docs/faq.md).
We'll also have more content soon in our [repository documentation](https://github.com/PowerShell/PowerShell/tree/master/docs) (which will eventually make its way to [official documentation](https://github.com/powershell/powershell-docs)).
In a nutshell, .NET Standard 2.0 allows us to have universal, portable modules between Windows PowerShell (which uses the full .NET Framework) and PowerShell Core (which uses .NET Core).
Many modules and cmdlets that didn't work in the past may now work on .NET Core, so import your favorite modules and tell us what does and doesn't work in our GitHub Issues!

### Telemetry

- For the first beta of PowerShell Core 6.0, telemetry has been to the console host to report two values (#3620):
    - the OS platform (`$PSVersionTable.OSDescription`)
    - the exact version of PowerShell (`$PSVersionTable.GitCommitId`)

If you want to opt-out of this telemetry, simply delete `$PSHome\DELETE_ME_TO_DISABLE_CONSOLEHOST_TELEMETRY`.
Even before the first run of Powershell, deleting this file will bypass all telemetry.
In the future, we plan on also enabling a configuration value for whatever is approved as part of [RFC0015](https://github.com/PowerShell/PowerShell-RFC/blob/master/1-Draft/RFC0015-PowerShell-StartupConfig.md).
We also plan on exposing this telemetry data (as well as whatever insights we leverage from the telemetry) in [our community dashboard](https://blogs.msdn.microsoft.com/powershell/2017/01/31/powershell-open-source-community-dashboard/).

If you have any questions or comments about our telemetry, please file an issue.

### Engine updates and fixes

- Add support for native command globbing on Unix platforms. (#3643)
    - This means you can now use wildcards with native binaries/commands (e.g. `ls *.txt`).
- Fix PowerShell Core to find help content from `$PSHome` instead of the Windows PowerShell base directory. (#3528)
    - This should fix issues where about_* topics couldn't be found on Unix platforms.
- Add the `OS` entry to `$PSVersionTable`. (#3654)
- Arrange the display of `$PSVersionTable` entries in the following way: (#3562) (Thanks to @iSazonov!)
    - `PSVersion`
    - `PSEdition`
    - alphabetical order for rest entries based on the keys
- Make PowerShell Core more resilient when being used with an account that doesn't have some key environment variables. (#3437)
- Update PowerShell Core to accept the `-i` switch to indicate an interactive shell. (#3558)
    - This will help when using PowerShell as a default shell on Unix platforms.
- Relax the PowerShell `SemanticVersion` constructors to not require 'minor' and 'patch' portions of a semantic version name. (#3696)
- Improve performance to security checks when group policies are in effect for ExecutionPolicy. (#2588) (Thanks to @powercode)
- Fix code in PowerShell to use `IntPtr(-1)` for `INVALID_HANDLE_VALUE` instead of `IntPtr.Zero`. (#3544) (Thanks to @0xfeeddeadbeef)

### General cmdlet updates and fixes

- Change the default encoding and OEM encoding used in PowerShell Core to be compatible with Windows PowerShell. (#3467) (Thanks to @iSazonov!)
- Fix a bug in `Import-Module` to avoid incorrect cyclic dependency detection. (#3594)
- Fix `New-ModuleManifest` to correctly check if a URI string is well formed. (#3631)

### Filesystem-specific updates and fixes

- Use operating system calls to determine whether two paths refer to the same file in file system operations. (#3441)
    - This will fix issues where case-sensitive file paths were being treated as case-insensitive on Unix platforms.
- Fix `New-Item` to allow creating symbolic links to file/directory targets and even a non-existent target. (#3509)
- Change the behavior of `Remove-Item` on a symbolic link to only removing the link itself. (#3637)
- Use better error message when `New-Item` fails to create a symbolic link because the specified link path points to an existing item. (#3703)
- Change `Get-ChildItem` to list the content of a link to a directory on Unix platforms. (#3697)
- Fix `Rename-Item` to allow Unix globbing patterns in paths. (#3661)

### Interactive fixes

- Add Hashtable tab completion for `-Property` of `Select-Object`. (#3625) (Thanks to @powercode)
- Fix tab completion with `@{<tab>` to avoid crash in PSReadline. (#3626) (Thanks to @powercode)
- Use `<id> - <name>` as `ToolTip` and `ListItemText` when tab completing process ID. (#3664) (Thanks to @powercode)

### Remoting fixes

- Update PowerShell SSH remoting to handle multi-line error messages from OpenSSH client. (#3612)
- Add `-Port` parameter to `New-PSSession` to create PowerShell SSH remote sessions on non-standard (non-22) ports. (#3499) (Thanks to @Lee303)

### API Updates

- Add the public property `ValidRootDrives` to `ValidateDriveAttribute` to make it easy to discover the attribute state via `ParameterMetadata` or `PSVariable` objects. (#3510) (Thanks to @indented-automation!)
- Improve error messages for `ValidateCountAttribute`. (#3656) (Thanks to @iSazonov)
- Update `ValidatePatternAttribute`, `ValidateSetAttribute` and `ValidateScriptAttribute` to allow users to more easily specify customized error messages. (#2728) (Thanks to @powercode)

## v6.0.0-alpha.18 - 2017-04-05

### Progress Bar

We made a number of fixes to the progress bar rendering and the `ProgressRecord` object that improved cmdlet performance and fixed some rendering bugs on non-Windows platforms.

- Fix a bug that caused the progress bar to drift on Unix platforms. (#3289)
- Improve the performance of writing progress records. (#2822) (Thanks to @iSazonov!)
- Fix the progress bar rendering on Unix platforms. (#3362) (#3453)
- Reuse `ProgressRecord` in Web Cmdlets to reduce the GC overhead. (#3411) (Thanks to @iSazonov!)

### Cmdlet updates

- Use `ShellExecute` with `Start-Process`, `Invoke-Item`, and `Get-Help -Online` so that those cmdlets use standard shell associations to open a file/URI.
  This means you `Get-Help -Online` will always use your default browser, and `Start-Process`/`Invoke-Item` can open any file or path with a handler.
  (Note: there are still some problems with STA threads.) (#3281, partially fixes #2969)
- Add `-Extension` and `-LeafBase` switches to `Split-Path` so that you can split paths between the filename extension and the rest of the filename. (#2721) (Thanks to @powercode!)
- Implement `Format-Hex` in C# along with some behavioral changes to multiple parameters and the pipeline. (#3320) (Thanks to @MiaRomero!)
- Add `-NoProxy` to web cmdlets so that they ignore the system-wide proxy setting. (#3447) (Thanks to @TheFlyingCorpse!)
- Fix `Out-Default -Transcript` to properly revert out of the `TranscribeOnly` state, so that further output can be displayed on Console. (#3436) (Thanks to @PetSerAl!)
- Fix `Get-Help` to not return multiple instances of the same help file. (#3410)

### Interactive fixes

- Enable argument auto-completion for `-ExcludeProperty` and `-ExpandProperty` of `Select-Object`. (#3443) (Thanks to @iSazonov!)
- Fix a tab completion bug that prevented `Import-Module -n<tab>` from working. (#1345)

### Cross-platform fixes

- Ignore the `-ExecutionPolicy` switch when running PowerShell on non-Windows platforms because script signing is not currently supported. (#3481)
- Standardize the casing of the `PSModulePath` environment variable. (#3255)

### JEA fixes

- Fix the JEA transcription to include the endpoint configuration name in the transcript header. (#2890)
- Fix `Get-Help` in a JEA session. (#2988)

## v6.0.0-alpha.17 - 2017-03-08

- Update PSRP client libraries for Linux and Mac.
    - We now support customer configurations for Office 365 interaction, as well as NTLM authentication for WSMan based remoting from Linux (more information [here](https://github.com/PowerShell/psl-omi-provider/releases/tag/v1.0.0.18)). (#3271)
- We now support remote step-in debugging for `Invoke-Command -ComputerName`. (#3015)
- Use prettier formatter with `ConvertTo-Json` output. (#2787) (Thanks to @kittholland!)
- Port `*-CmsMessage` and `Get-PfxCertificate` cmdlets to Powershell Core. (#3224)
- `powershell -version` now returns version information for PowerShell Core. (#3115)
- Add the `-TimeOut` parameter to `Test-Connection`. (#2492)
- Add `ShouldProcess` support to `New-FileCatalog` and `Test-FileCatalog` (fixes `-WhatIf` and `-Confirm`). (#3074) (Thanks to @iSazonov!)
- Fix `Test-ModuleManifest` to normalize paths correctly before validating.
  - This fixes some problems when using `Publish-Module` on non-Windows platforms. (#3097)
- Remove the `AliasProperty "Count"` defined for `System.Array`.
  - This removes the extraneous `Count` property on some `ConvertFrom-Json` output. (#3231) (Thanks to @PetSerAl!)
- Port `Import-PowerShellDatafile` from PowerShell script to C#. (#2750) (Thanks to @powercode!)
- Add `-CustomMethod` parameter to web cmdlets to allow for non-standard method verbs. (#3142) (Thanks to @Lee303!)
- Fix web cmdlets to include the HTTP response in the exception when the response status code is not success. (#3201)
- Expose a process' parent process by adding the `CodeProperty "Parent"` to `System.Diagnostics.Process`. (#2850) (Thanks to @powercode!)
- Fix crash when converting a recursive array to a bool. (#3208) (Thanks to @PetSerAl!)
- Fix casting single element array to a generic collection. (#3170)
- Allow profile directory creation failures for Service Account scenarios. (#3244)
- Allow Windows' reserved device names (e.g. CON, PRN, AUX, etc.) to be used on non-Windows platforms. (#3252)
- Remove duplicate type definitions when reusing an `InitialSessionState` object to create another Runspace. (#3141)
- Fix `PSModuleInfo.CaptureLocals` to not do `ValidateAttribute` check when capturing existing variables from the caller's scope. (#3149)
- Fix a race bug in WSMan command plug-in instance close operation. (#3203)
- Fix a problem where newly mounted volumes aren't available to modules that have already been loaded. (#3034)
- Remove year from PowerShell copyright banner at start-up. (#3204) (Thanks to @kwiknick!)
- Fixed spelling for the property name `BiosSerialNumber` for `Get-ComputerInfo`. (#3167) (Thanks to @iSazonov!)

## v6.0.0-alpha.16 - 2017-02-15

- Add `WindowsUBR` property to `Get-ComputerInfo` result
- Cache padding strings to speed up formatting a little
- Add alias `Path` to the `-FilePath` parameter of `Out-File`
- Fix the `-InFile` parameter of `Invoke-WebRequest`
- Add the default help content to powershell core
- Speed up `Add-Type` by crossgen'ing its dependency assemblies
- Convert `Get-FileHash` from script to C# implementation
- Fix lock contention when compiling the code to run in interpreter
- Avoid going through WinRM remoting stack when using `Get-ComputerInfo` locally
- Fix native parameter auto-completion for tokens that begin with a single "Dash"
- Fix parser error reporting for incomplete input to allow defining class in interactive host
- Add the `RoleCapabilityFiles` keyword for JEA support on Windows

## v6.0.0-alpha.15 - 2017-01-18

- Use parentheses around file length for offline files
- Fix issues with the Windows console mode (terminal emulation) and native executables
- Fix error recovery with `using module`
- Report `PlatformNotSupported` on IoT for Get/Import/Export-Counter
- Add `-Group` parameter to `Get-Verb`
- Use MB instead of KB for memory columns of `Get-Process`
- Add new escape character for ESC: `` `e``
- Fix a small parsing issue with a here string
- Improve tab completion of types that use type accelerators
- `Invoke-RestMethod` improvements for non-XML non-JSON input
- PSRP remoting now works on CentOS without addition setup

## v6.0.0-alpha.14 - 2016-12-14

- Moved to .NET Core 1.1
- Add Windows performance counter cmdlets to PowerShell Core
- Fix try/catch to choose the more specific exception handler
- Fix issue reloading modules that define PowerShell classes
- `Add ValidateNotNullOrEmpty` to approximately 15 parameters
- `New-TemporaryFile` and `New-Guid` rewritten in C#
- Enable client side PSRP on non-Windows platforms
- `Split-Path` now works with UNC roots
- Implicitly convert value assigned to XML property to string
- Updates to `Invoke-Command` parameters when using SSH remoting transport
- Fix `Invoke-WebRequest` with non-text responses on non-Windows platforms
- `Write-Progress` performance improvement from `alpha13` reverted because it introduced crash with a race condition

## v6.0.0-alpha.13 - 2016-11-22

- Fix `NullReferenceException` in binder after turning on constrained language mode
- Enable `Invoke-WebRequest` and `Invoke-RestMethod` to not validate the HTTPS certificate of the server if required.
- Enable binder debug logging in PowerShell Core
- Add parameters `-Top` and `-Bottom` to `Sort-Object` for Top/Bottom N sort
- Enable `Update-Help` and `Save-Help` on Unix platforms
- Update the formatter for `System.Diagnostics.Process` to not show the `Handles` column
- Improve `Write-Progress` performance by adding timer to update a progress pane every 100 ms
- Enable correct table width calculations with ANSI escape sequences on Unix
- Fix background jobs for Unix and Windows
- Add `Get-Uptime` to `Microsoft.PowerShell.Utility`
- Make `Out-Null` as fast as `> $null`
- Add DockerFile for 'Windows Server Core' and 'Nano Server'
- Fix WebRequest failure to handle missing ContentType in response header
- Make `Write-Host` fast by delay initializing some properties in InformationRecord
- Ensure PowerShell Core adds an initial `/` rooted drive on Unix platforms
- Enable streaming behavior for native command execution in pipeline, so that `ping | grep` doesn't block
- Make `Write-Information` accept objects from pipeline
- Fixes deprecated syscall issue on macOS 10.12
- Fix code errors found by the static analysis using PVS-Studio
- Add support to W3C Extended Log File Format in `Import-Csv`
- Guard against `ReflectionTypeLoadException` in type name auto-completion
- Update build scripts to support win7-x86 runtime
- Move PackageManagement code/test to oneget.org

## v6.0.0-alpha.12 - 2016-11-03

- Fix `Get-ChildItem -Recurse -ErrorAction Ignore` to ignore additional errors
- Don't block pipeline when running Windows EXE's
- Fix for PowerShell SSH remoting with recent Win32-OpenSSH change.
- `Select-Object` with `-ExcludeProperty` now implies `-Property *` if -Property is not specified.
- Adding ValidateNotNullOrEmpty to `-Name` parameter of `Get-Alias`
- Enable Implicit remoting commands in PowerShell Core
- Fix GetParentProcess() to replace an expensive WMI query with Win32 API calls
- Fix `Set-Content` failure to create a file in PSDrive under certain conditions.
- Adding ValidateNotNullOrEmpty to `-Name` parameter of `Get-Service`
- Adding support <Suppress> in `Get-WinEvent -FilterHashtable`
- Adding WindowsVersion to `Get-ComputerInfo`
- Remove the unnecessary use of lock in PseudoParameterBinder to avoid deadlock
- Refactor `Get-WinEvent` to use StringBuilder for XPath query construction
- Clean up and fix error handling of libpsl-native
- Exclude Registry and Certificate providers from UNIX PS
- Update PowerShell Core to consume .Net Core preview1-24530-04

## v6.0.0-alpha.11 - 2016-10-17

- Add '-Title' to 'Get-Credential' and unify the prompt experience
- Update dependency list for PowerShell Core on Linux and OS X
- Fix 'powershell -Command -' to not hang and to not ignore the last command
- Fix binary operator tab completion
- Enable 'ConvertTo-Html' in PowerShell Core
- Remove most Maximum* capacity variables
- Fix 'Get-ChildItem -Hidden' to work on system hidden files on Windows
- Fix 'JsonConfigFileAccessor' to handle corrupted 'PowerShellProperties.json'
    and defer creating the user setting directory until a write request comes
- Fix variable assignment to not overwrite read-only variables
- Fix 'Get-WinEvent -FilterHashtable' to work with named fields in UserData of event logs
- Fix 'Get-Help -Online' in PowerShell Core on Windows
- Spelling/grammar fixes

## v6.0.0-alpha.10 - 2016-09-15

- Fix passing escaped double quoted spaces to native executables
- Add DockerFiles to build each Linux distribution
- `~/.config/PowerShell` capitalization bug fixed
- Fix crash on Windows 7
- Fix remote debugging on Windows client
- Fix multi-line input with redirected stdin
- Add PowerShell to `/etc/shells` on installation
- Fix `Install-Module` version comparison bug
- Spelling fixes

## v6.0.0-alpha.9 - 2016-08-15

- Better man page
- Added third-party and proprietary licenses
- Added license to MSI

## v6.0.0-alpha.8 - 2016-08-11

- PowerShell packages pre-compiled with crossgen
- `Get-Help` content added
- `Get-Help` null reference exception fixed
- Ubuntu 16.04 support added
- Unsupported cmdlets removed from Unix modules
- PSReadline long prompt bug fixed
- PSReadline custom key binding bug on Linux fixed
- Default terminal colors now respected
- Semantic Version support added
- `$env:` fixed for case-sensitive variables
- Added JSON config files to hold some settings
- `cd` with no arguments now behaves as `cd ~`
- `ConvertFrom-Json` fixed for multiple lines
- Windows branding removed
- .NET CoreCLR Runtime patched to version 1.0.4
- `Write-Host` with unknown hostname bug fixed
- `powershell` man-page added to package
- `Get-PSDrive` ported to report free space
- Desired State Configuration MOF compilation ported to Linux
- Windows 2012 R2 / Windows 8.1 remoting enabled

## v6.0.0-alpha.7 - 2016-07-26

- Invoke-WebRequest and Invoke-RestMethod ported to PowerShell Core
- Set PSReadline default edit mode to Emacs on Linux
- IsCore variable renamed to IsCoreCLR
- Microsoft.PowerShell.LocalAccounts and other Windows-only assemblies excluded on Linux
- PowerShellGet fully ported to Linux
- PackageManagement NuGet provider ported
- Write-Progress ported to Linux
- Get-Process -IncludeUserName ported
- Enumerating symlinks to folders fixed
- Bugs around administrator permissions fixed on Linux
- ConvertFrom-Json multi-line bug fixed
- Execution policies fixed on Windows
- TimeZone cmdlets added back; excluded from Linux
- FileCatalog cmdlets added back for Windows
- Get-ComputerInfo cmdlet added back for Windows

## v0.6.0 - 2016-07-08

- Targets .NET Core 1.0 release
- PowerShellGet enabled
- [system.manage<tab>] completion issues fixed
- AssemblyLoadContext intercepts dependencies correctly
- Type catalog issues fixed
- Invoke-Item enabled for Linux and OS X
- Windows ConsoleHost reverted to native interfaces
- Portable ConsoleHost redirection issues fixed
- Bugs with pseudo (and no) TTY's fixed
- Source Depot synced to baseline changeset 717473
- SecureString stub replaced with .NET Core package

## v0.5.0 - 2016-06-16

- Paths given to cmdlets are now slash-agnostic (both / and \ work as directory separator)
- Lack of cmdlet support for paths with literal \ is a known issue
- .NET Core packages downgraded to build rc2-24027 (Nano's build)
- XDG Base Directory Specification is now respected and used by default
- Linux and OS X profile path is now `~/.config/powershell/profile.ps1`
- Linux and OS X history save path is now `~/.local/share/powershell/PSReadLine/ConsoleHost_history.txt`
- Linux and OS X user module path is now `~/.local/share/powershell/Modules`
- The `~/.powershell` folder is deprecated and should be deleted
- Scripts can be called within PowerShell without the `.ps1` extension
- `Trace-Command` and associated source cmdlets are now available
- `Ctrl-C` now breaks running cmdlets correctly
- Source Depot changesets up to 715912 have been merged
- `Set-PSBreakPoint` debugging works on Linux, but not on Windows
- MSI and APPX packages for Windows are now available
- Microsoft.PowerShell.LocalAccounts is available on Windows
- Microsoft.PowerShell.Archive is available on Windows
- Linux xUnit tests are running again
- Many more Pester tests are running

## v0.4.0 - 2016-05-17

- PSReadline is ported and included by default
- Original Windows ConsoleHost is ported and replaced CoreConsoleHost
- .NET Core packages set to the RC2 release at build 24103
- OS X 10.11 added to Continuous Integration matrix
- Third-party C# cmdlets can be built with .NET CLI
- Improved symlink support on Linux
- Microsoft.Management.Infrastructure.Native replaced with package
- Many more Pester tests

## v0.3.0 - 2016-04-11

- Supports Windows, Nano, OS X, Ubuntu 14.04, and CentOS 7.1
- .NET Core packages are build rc3-24011
- Native Linux commands are not shadowed by aliases
- `Get-Help -Online` works
- `more` function respects the Linux `$PAGER`; defaults to `less`
- `IsWindows`, `IsLinux`, `IsOSX`, `IsCore` built-in PowerShell variables added
- `Microsoft.PowerShell.Platform` removed for the above
- Cross-platform core host is now `CoreConsoleHost`
- Host now catches exceptions in `--command` scripts
- Host's shell ID changed to `Microsoft.PowerShellCore`
- Modules that use C# assemblies can be loaded
- `New-Item -ItemType SymbolicLink` supports arbitrary targets
- PSReadline implementation supports multi-line input
- `Ctrl-R` provides incremental reverse history search
- `$Host.UI.RawUI` now supported
- `Ctrl-K` and `Ctrl-Y` for kill and yank implemented
- `Ctrl-L` to clear screen now works
- Documentation was completely overhauled
- Many more Pester and xUnit tests added

## v0.2.0 - 2016-03-08

- Supports Windows, OS X, Ubuntu 14.04, and CentOS 7.1
- .NET Core packages are build 23907
- `System.Console` PSReadline is fully functional
- Tests pass on OS X
- `Microsoft.PowerShell.Platform` module is available
- `New-Item` supports symbolic and hard links
- `Add-Type` now works
- PowerShell code merged with upstream `rs1_srv_ps`

## v0.1.0 - 2016-02-23

- Supports Windows, OS X, and Ubuntu 14.04
