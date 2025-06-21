# time2backup tests

source tests/00_init.sh

@test "t2b --version" {
	run t2b --version
	[ -n "$output" ]
	[ "$status" = 0 ]
}

@test "default: t2b backup" {
	# initialize test environment
	t2b_init default

	run t2b backup
	[ -n "$output" ]
	[ "$status" = 0 ]
}

@test "default: t2b history badFile" {
	run t2b history badFile
	[ "$status" = 5 ]
}

@test "default: t2b history \$test_file" {
	run t2b_history
	[ -n "$output" ]
	[ "$status" = 0 ]
}

@test "default: t2b delete & restore \$test_file" {
	run t2b_restore
	[ -n "$output" ]
	[ "$status" = 0 ]
}
