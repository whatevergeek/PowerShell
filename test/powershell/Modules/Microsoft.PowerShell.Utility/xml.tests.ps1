﻿Describe "XML cmdlets" -Tags "Feature" {
    Context "Select-XML" {
        BeforeAll {
            $fileName = New-Item -Path 'TestDrive:\testSelectXml.xml'
	        Push-Location "$fileName\.."
	        "<Root>" | out-file -LiteralPath $fileName
	        "   <Node Attribute='blah' />" | out-file -LiteralPath $fileName -Append
	        "</Root>" | out-file -LiteralPath $fileName -Append

            $fileNameWithDots = $fileName.FullName.Replace("\", "\.\")

            $driveLetter = [string]($fileName.FullName)[0]
	        $fileNameAsNetworkPath = "\\localhost\$driveLetter`$" + $fileName.FullName.SubString(2)

            class TestData
            {
                [string] $testName
                [hashtable] $parameters

                TestData($name, $parameters)
                {
                    $this.testName = $name
                    $this.parameters = $parameters
                }
            }

            $testcases = @()
            $testcases += [TestData]::new('literalpath with relative paths', @{LiteralPath = $fileName.Name; XPath = 'Root'})
            $testcases += [TestData]::new('literalpath with absolute paths', @{LiteralPath = $fileName.FullName; XPath = 'Root'})
            $testcases += [TestData]::new('literalpath with path with dots', @{LiteralPath = $fileNameWithDots; XPath = 'Root'})
            if ( ! $IsCoreCLR ) {
                $testcases += [TestData]::new('literalpath with network path', @{LiteralPath = $fileNameAsNetworkPath; XPath = 'Root'})
            }
            $testcases += [TestData]::new('path with relative paths', @{Path = $fileName.Name; XPath = 'Root'})
            $testcases += [TestData]::new('path with absolute paths', @{Path = $fileName.FullName; XPath = 'Root'})
            $testcases += [TestData]::new('path with path with dots', @{Path = $fileNameWithDots; XPath = 'Root'})
            if ( ! $IsCoreCLR ) {
                $testcases += [TestData]::new('path with network path', @{Path = $fileNameAsNetworkPath; XPath = 'Root'})
            }
        }

        AfterAll {
            Remove-Item -LiteralPath $fileName -Force -ErrorAction SilentlyContinue
            Pop-Location
        }

        $testcases | ForEach-Object {

            $params = $_.parameters

            It $_.testName {
                @(Select-XML @params).Count | Should Be 1
                (Select-XML @params).Path | Should Be $fileName.FullName
            }
        }

        It "non filesystem path using <parameter>" -TestCases @(
            @{parameter="literalPath"},
            @{parameter="path"}
        ) {
            param($parameter)
            $__data = "abcdefg"
            $params = @{$parameter="variable:__data"}
            { Select-XML @params "Root" | Should BeErrorId 'ProcessingFile,Microsoft.PowerShell.Commands.SelectXmlCommand' }
        }

        It "Invalid xml file" {
            $testfile = "$testdrive/test.xml"
            Set-Content -Path $testfile -Value "<a><b>"
            { Select-Xml -Path $testfile -XPath foo | ShouldBeErrorId 'ProcessingFile,Microsoft.PowerShell.Commands.SelectXmlCommand' }
        }

        It "-xml works with inputstream" {
            [xml]$xml = "<a xmlns='bar'><b xmlns:b='foo'>hello</b><c>world</c></a>"
            $node = Select-Xml -Xml $xml -XPath "//c:b" -Namespace @{c='bar'}
            $node.Path | Should BeExactly "InputStream"
            $node.Pattern = "//c:b"
            $node.ToString() | Should BeExactly "hello"
        }

        It "Returns error for invalid xmlnamespace" {
            [xml]$xml = "<a xmlns='bar'><b xmlns:b='foo'>hello</b><c>world</c></a>"
            { Select-Xml -Xml $xml -XPath foo -Namespace @{c=$null} | ShouldBeErrorId "PrefixError,Microsoft.PowerShell.Commands.SelectXmlCommand" }
        }

        It "Returns error for invalid content" {
            { Select-Xml -Content "hello" -XPath foo | ShouldBeErrorId "InvalidCastToXmlDocument,Microsoft.PowerShell.Commands.SelectXmlCommand" }
        }

        It "ToString() works correctly on nested node" {
            $node = Select-Xml -Content "<a><b>one<c>hello</c></b></a>" -XPath "//b"
            $node.ToString() | Should BeExactly "one<c>hello</c>"
        }

        It "ToString() works correctly with file" {
            $testfile = Join-Path "$testdrive" "test.xml"
            Set-Content -Path $testfile -Value "<a><b>hello</b></a>"
            $node = Select-Xml -Path $testfile -XPath "//b"
            $node.ToString() | Should BeExactly "hello:$testfile"
        }
    }
}
