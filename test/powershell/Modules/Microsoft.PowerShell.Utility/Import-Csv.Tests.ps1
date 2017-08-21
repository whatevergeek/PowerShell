Describe "Import-Csv DRT Unit Tests" -Tags "CI" {
    BeforeAll {
        $fileToGenerate = Join-Path $TestDrive -ChildPath "importCSVTest.csv"
        $psObject = [pscustomobject]@{ "First" = "1"; "Second" = "2" }
    }

    It "Test import-csv with a delimiter parameter" {
        $delimiter = ';'
        $psObject | Export-Csv -Path $fileToGenerate -Delimiter $delimiter
        $returnObject = Import-Csv -Path $fileToGenerate -Delimiter $delimiter
        $returnObject.First | Should Be 1
        $returnObject.Second | Should Be 2
    }

    It "Test import-csv with UseCulture parameter" {
        $psObject | Export-Csv -Path $fileToGenerate -UseCulture
        $returnObject = Import-Csv -Path $fileToGenerate -UseCulture
        $returnObject.First | Should Be 1
        $returnObject.Second | Should Be 2
    }
}

Describe "Import-Csv File Format Tests" -Tags "CI" {
    BeforeAll {
        # The file is w/o header
        $TestImportCsv_NoHeader = Join-Path -Path (Join-Path $PSScriptRoot -ChildPath assets) -ChildPath TestImportCsv_NoHeader.csv
        # The file is with header
        $TestImportCsv_WithHeader = Join-Path -Path (Join-Path $PSScriptRoot -ChildPath assets) -ChildPath TestImportCsv_WithHeader.csv
        # The file is W3C Extended Log File Format
        $TestImportCsv_W3C_ELF = Join-Path -Path (Join-Path $PSScriptRoot -ChildPath assets) -ChildPath TestImportCsv_W3C_ELF.csv

        $testCSVfiles = $TestImportCsv_NoHeader, $TestImportCsv_WithHeader, $TestImportCsv_W3C_ELF
        $orginalHeader = "Column1","Column2","Column 3"
        $customHeader = "test1","test2","test3"
    }
    # Test set is the same for all file formats
    foreach ($testCsv in $testCSVfiles) {
       $FileName = (dir $testCsv).Name
        Context "Next test file: $FileName" {
            BeforeAll {
                $CustomHeaderParams = @{Header = $customHeader; Delimiter = ","}
                if ($FileName -eq "TestImportCsv_NoHeader.csv") {
                    # The file does not have header
                    # (w/o Delimiter here we get throw (bug?))
                    $HeaderParams = @{Header = $orginalHeader; Delimiter = ","}
                } else {
                    # The files have header
                    $HeaderParams = @{Delimiter = ","}
                }

            }

            It "Should be able to import all fields" {
                $actual = Import-Csv -Path $testCsv @HeaderParams
                $actualfields = $actual[0].psobject.Properties.Name
                $actualfields | Should Be $orginalHeader
            }

            It "Should be able to import all fields with custom header" {
                $actual = Import-Csv -Path $testCsv @CustomHeaderParams
                $actualfields = $actual[0].psobject.Properties.Name
                $actualfields | Should Be $customHeader
            }

            It "Should be able to import correct values" {
                $actual = Import-Csv -Path $testCsv @HeaderParams
                $actual.count         | Should Be 4
                $actual[0].'Column1'  | Should Be "data1"
                $actual[0].'Column2'  | Should Be "1"
                $actual[0].'Column 3' | Should Be "A"
            }

        }
    }
}

Describe "Import-Csv #Type Tests" -Tags "CI" {
    BeforeAll {
        $testfile = Join-Path $TestDrive -ChildPath "testfile.csv"
        Remove-Item -Path $testfile -Force -ErrorAction SilentlyContinue
        $processlist = (Get-Process)[0..1]
        $processlist | Export-Csv -Path $testfile -Force
        # Import-Csv add "CSV:" before actual type
        $expectedProcessType = "CSV:System.Diagnostics.Process"
    }

    It "Test import-csv import Object" {
        $importObjectList = Import-Csv -Path $testfile
        $processlist.Count | Should Be $importObjectList.Count

        $importType = $importObjectList[0].psobject.TypeNames[0]
        $importType | Should Be $expectedProcessType
    }
}
