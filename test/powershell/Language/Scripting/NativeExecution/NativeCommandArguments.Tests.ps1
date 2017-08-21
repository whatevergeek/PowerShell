Describe "Native Command Arguments" -tags "CI" {
    # When passing arguments to native commands, quoted segments that contain
    # spaces need to be quoted with '"' characters when they are passed to the
    # native command (or to bash or sh on Linux).
    #
    # This test checks that the proper quoting is occuring by passing arguments
    # to the testexe native command and looking at how it got the arguments.
    It "Should handle quoted spaces correctly" {
        $a = 'a"b c"d'
        $lines = testexe -echoargs $a 'a"b c"d' a"b c"d
        ($lines | measure).Count | Should Be 3
        $lines[0] | Should Be 'Arg 0 is <ab cd>'
        $lines[1] | Should Be 'Arg 1 is <ab cd>'
        $lines[2] | Should Be 'Arg 2 is <ab cd>'
    }

    # In order to pass '"' characters so they are actually part of command line
    # arguments for native commands, they need to be escaped with a '\' (this
    # is in addition to the '`' escaping needed inside '"' quoted strings in
    # PowerShell).
    #
    # This functionality was broken in PowerShell 5.0 and 5.1, so this test
    # will fail on those versions unless the fix is backported to them.
    #
    # This test checks that the proper quoting and escaping is occurring by
    # passing arguments with escaped quotes to the testexe native command and
    # looking at how it got the arguments.
    It "Should handle spaces between escaped quotes" {
        $lines = testexe -echoargs 'a\"b c\"d' "a\`"b c\`"d"
        ($lines | measure).Count | Should Be 2
        $lines[0] | Should Be 'Arg 0 is <a"b c"d>'
        $lines[1] | Should Be 'Arg 1 is <a"b c"d>'
    }
}
