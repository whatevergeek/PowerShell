Describe "Move-Item tests" -Tag "CI" {
    BeforeAll {
        $content = "This is content"
        Setup -f originalfile.txt -content "This is content"
        $source = "$TESTDRIVE/originalfile.txt"
        $target = "$TESTDRIVE/ItemWhichHasBeenMoved.txt"
    }
    It "Move-Item will move a file" {
        Move-Item $source $target
        test-path $source | Should be $false
        test-path $target | Should be $true
        "$target" | Should ContainExactly "This is content"
    }

    Context "Move-Item with filters" {
        BeforeAll {
            $filterPath = "$TESTDRIVE/filterTests"
            $moveToPath = "$TESTDRIVE/dest-dir"
            $renameToPath = Join-Path $filterPath "move.txt"
            $filePath = Join-Path $filterPath "*"
            $fooFile = "foo.txt"
            $barFile = "bar.txt"
            $booFile = "boo.txt"
            $fooPath = Join-Path $filterPath $fooFile
            $barPath = Join-Path $filterPath $barFile
            $booPath = Join-Path $filterPath $booFile
            $newFooPath = Join-Path $moveToPath $fooFile
            $newBarPath = Join-Path $moveToPath $barFile
            $newBooPath = Join-Path $moveToPath $booFile
            $fooContent = "foo content"
            $barContent = "bar content"
            $booContent = "boo content"
        }
        BeforeEach {
            New-Item -ItemType Directory -Path $filterPath | Out-Null
            New-Item -ItemType Directory -Path $moveToPath | Out-Null
            New-Item -ItemType File -Path $fooPath -Value $fooContent | Out-Null
            New-Item -ItemType File -Path $barPath -Value $barContent | Out-Null
            New-Item -ItemType File -Path $booPath -Value $booContent | Out-Null
        }
        AfterEach {
            Remove-Item $filterPath -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $moveToPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        It "Can move to different directory, filtered with -Include" {
            Move-Item -Path $filePath -Destination $moveToPath -Include "bar*" -ErrorVariable e -ErrorAction SilentlyContinue
            $e | Should BeNullOrEmpty
            $barPath | Should Not Exist
            $newBarPath | Should Exist
            $booPath | Should Exist
            $fooPath | Should Exist
            $newBarPath | Should ContainExactly $barContent
        }
        It "Can move to different directory, filtered with -Exclude" {
            Move-Item -Path $filePath -Destination $moveToPath -Exclude "b*" -ErrorVariable e -ErrorAction SilentlyContinue
            $e | Should BeNullOrEmpty
            $fooPath | Should Not Exist
            $newFooPath | Should Exist
            $booPath | Should Exist
            $barPath | Should Exist
            $newFooPath | Should ContainExactly $fooContent
        }
        It "Can move to different directory, filtered with -Filter" {
            Move-Item -Path $filePath -Destination $moveToPath -Filter "bo*" -ErrorVariable e -ErrorAction SilentlyContinue
            $e | Should BeNullOrEmpty
            $booPath | Should Not Exist
            $newBooPath | Should Exist
            $barPath | Should Exist
            $fooPath | Should Exist
            $newBooPath | Should ContainExactly $booContent
        }

        It "Can rename via move, filtered with -Include" {
            Move-Item -Path $filePath -Destination $renameToPath -Include "bar*" -ErrorVariable e -ErrorAction SilentlyContinue
            $e | Should BeNullOrEmpty
            $renameToPath | Should Exist
            $barPath | Should Not Exist
            $booPath | Should Exist
            $fooPath | Should Exist
            $renameToPath | Should ContainExactly $barContent
        }
        It "Can rename via move, filtered with -Exclude" {
            Move-Item -Path $filePath -Destination $renameToPath -Exclude "b*" -ErrorVariable e -ErrorAction SilentlyContinue
            $e | Should BeNullOrEmpty
            $renameToPath | Should Exist
            $fooPath | Should Not Exist
            $booPath | Should Exist
            $barPath | Should Exist
            $renameToPath | Should ContainExactly $fooContent
        }
        It "Can rename via move, filtered with -Filter" {
            Move-Item -Path $filePath -Destination $renameToPath -Filter "bo*" -ErrorVariable e -ErrorAction SilentlyContinue
            $e | Should BeNullOrEmpty
            $renameToPath | Should Exist
            $booPath | Should Not Exist
            $fooPath | Should Exist
            $barPath | Should Exist
            $renameToPath | Should ContainExactly $booContent
        }
    }
}
