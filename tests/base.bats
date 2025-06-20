# time2backup tests

alias t2b='./time2backup.sh'

@test "t2b --version" {
	run t2b --version
	[ -n "$output" ]
	[ "$status" = 0 ]
}
