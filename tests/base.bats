# time2backup tests

@test "t2b --version" {
	run ./time2backup --version
	[ -n "$output" ]
	[ "$status" = 0 ]
}
