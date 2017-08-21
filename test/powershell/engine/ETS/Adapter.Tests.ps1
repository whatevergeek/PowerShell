Describe "Adapter Tests" -tags "CI" {
    BeforeAll {
        $pso  = [System.Diagnostics.Process]::GetCurrentProcess()
        $processName = $pso.Name

        if(-not ('TestCodeMethodClass' -as "type"))
        {
            class TestCodeMethodClass {
                static [int] TestCodeMethod([PSObject] $target, [int] $i)
                {
                    return 1;
                }
            }
        }

        $psmemberset = new-object System.Management.Automation.PSMemberSet 'setname1'
        $psmemberset | Add-Member -MemberType NoteProperty -Name NoteName -Value 1
        $testmethod = [TestCodeMethodClass].GetMethod("TestCodeMethod")
        $psmemberset | Add-Member -MemberType CodeMethod -Name TestCodeMethod -Value $testmethod

        $document = new-object System.Xml.XmlDocument
        $document.LoadXml("<book ISBN='12345'><title>Pride And Prejudice</title><price>19.95</price></book>")
        $doc = $document.DocumentElement
    }
    It "can get a Dotnet parameterized property" {
        $col  = $pso.psobject.Properties.Match("*")
        $prop = $col.psobject.Members["Item"]
        $prop | Should Not BeNullOrEmpty
        $prop.IsGettable | Should be $true
        $prop.IsSettable | Should be $false
        $prop.TypeNameOfValue | Should be "System.Management.Automation.PSPropertyInfo"
        $prop.Invoke("ProcessName").Value | Should be $processName
    }

    It "can get a property" {
        $pso.psobject.Properties["ProcessName"] | should Not BeNullOrEmpty
    }

    It "Can access all properties" {
        $props = $pso.psobject.Properties.Match("*")
        $props | should Not BeNullOrEmpty
        $props["ProcessName"].Value |Should be $processName
    }

    It "Can invoke a method" {
        $method = $pso.psobject.Methods["ToString"]
        $method.Invoke()  | should be ($pso.ToString())
    }

    It "Access a Method via MemberSet adapter" {
        $prop = $psmemberset.psobject.Members["TestCodeMethod"]
        $prop.Invoke(2) | Should be 1
    }

    It "Access misc properties via MemberSet adapter" {
        $prop  = $psmemberset.psobject.Properties["NoteName"]
        $prop | Should Not BeNullOrEmpty
        $prop.IsGettable | Should be $true
        $prop.IsSettable | Should be $true
        $prop.TypeNameOfValue | Should be "System.Int32"
    }

    It "Access all the properties via XmlAdapter" {
        $col  = $doc.psobject.Properties.Match("*")
        $col.Count | Should Not Be 0
        $prop = $col["price"]
        $prop | Should Not BeNullOrEmpty
    }

    It "Access all the properties via XmlAdapter" {
        $prop  = $doc.psobject.Properties["price"]
        $prop.Value | Should Be "19.95"
        $prop.IsGettable | Should Not BeNullOrEmpty
        $prop.IsSettable | Should Not BeNullOrEmpty
        $prop.TypeNameOfValue | Should be "System.String"
    }

    It "Call to string on a XmlNode object" {
        $val  = $doc.ToString()
        $val | Should Be "book"
    }
}

Describe "Adapter XML Tests" -tags "CI" {
    BeforeAll {
        [xml]$x  = "<root><data/></root>"
        $testCases =
            @{ rval = @{testprop = 1}; value = 'a hash (psobject)' },
            @{ rval = $null;           value = 'a null (codemethod)' },
            @{ rval = 1;               value = 'a int (codemethod)' },
            @{ rval = "teststring";    value = 'a string (codemethod)' },
            @{ rval = @("teststring1", "teststring2");  value = 'a string array (codemethod)' },
            @{ rval = @(1,2); value = 'a int array (codemethod)' },
            @{ rval = [PSObject]::AsPSObject(1); value = 'a int (psobject wrapping)' },
            @{ rval = [PSObject]::AsPSObject("teststring"); value = 'a string (psobject wrapping)' },
            @{ rval = [PSObject]::AsPSObject([psobject]@("teststring1", "teststring2")); value = 'a string array (psobject wrapping)' },
            @{ rval = [PSObject]::AsPSObject(@(1,2)); value = 'int array (psobject wrapping)' }
    }

    Context "Can set XML node property to non-string object" {
        It "rval is <value>" -TestCases $testCases {
            # rval will be implicitly converted to 'string' type
            param($rval)
            {
                { $x.root.data = $rval } | Should Not Throw
                $x.root.data | Should Be [System.Management.Automation.LanguagePrimitives]::ConvertTo($rval, [string])
            }
        }
    }
}

Describe "DataRow and DataRowView Adapter tests" -tags "CI" {

    BeforeAll {
        ## Define the DataTable schema
        $dataTable = [System.Data.DataTable]::new("inputs")
        $dataTable.Locale = [cultureinfo]::InvariantCulture
        $dataTable.Columns.Add("Id", [int]) > $null
        $dataTable.Columns.Add("FirstName", [string]) > $null
        $dataTable.Columns.Add("LastName", [string]) > $null
        $dataTable.Columns.Add("YearsInMS", [int]) > $null

        ## Add data entries
        $dataTable.Rows.Add(@(1, "joseph", "smith", 15)) > $null
        $dataTable.Rows.Add(@(2, "paul", "smith", 15)) > $null
        $dataTable.Rows.Add(@(3, "mary jo", "soe", 5)) > $null
        $dataTable.Rows.Add(@(4, "edmund`todd `n", "bush", 9)) > $null
    }

    Context "DataRow Adapter tests" {

        It "Should be able to access data columns" {
            $row = $dataTable.Rows[0]
            $row.Id | Should Be 1
            $row.FirstName | Should Be "joseph"
            $row.LastName | Should Be "smith"
            $row.YearsInMS | Should Be 15
        }

        It "DataTable should be enumerable in PowerShell" {
            ## Get the third entry in the data table
            $row = $dataTable | Select-Object -Skip 2 -First 1
            $row.Id | Should Be 3
            $row.FirstName | Should Be "mary jo"
            $row.LastName | Should Be "soe"
            $row.YearsInMS | Should Be 5
        }
    }

    Context "DataRowView Adapter tests" {

        It "Should be able to access data columns" {
            $rowView = $dataTable.DefaultView[1]
            $rowView.Id | Should Be 2
            $rowView.FirstName | Should Be "paul"
            $rowView.LastName | Should Be "smith"
            $rowView.YearsInMS | Should Be 15
        }

        It "DataView should be enumerable" {
            $rowView = $dataTable.DefaultView | Select-Object -Last 1
            $rowView.Id | Should Be 4
            $rowView.FirstName | Should Be "edmund`todd `n"
            $rowView.LastName | Should Be "bush"
            $rowView.YearsInMS | Should Be 9
        }
    }
}
