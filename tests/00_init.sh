# time2backup script to initialize environment

# source files path
src=tests/files/src

# file to test for restorations
test_file="$src/dir 1/subdir 11/file 111"

# short command to run time2backup easely
t2b() {
	# options: console mode, force config path + backup path
	./time2backup.sh -c tests/files/config -d tests/files/backups "$@"
}

# initialize files
t2b_init() {
	# clean old files
	rm -rf tests/files

	# Create source files
	#    files/src/
	#             dir 1/
	#                subdir 11/
	#                   file 111
	#                   ...
	#                   file 11N
	#                ...
	#                subdir 1N/
	#                   file 1N1
	#                   ...
	#                   file 1NN
	#             ...
	#             dir N/
	#                subdir N1/
	#                   file N11
	#                   ...
	#                   file N1N
	#                ...
	#                subdir NN/
	#                   file NN1
	#                   ...
	#                   file NNN

	# number max to iterate
	n=3

	# main dirs
	for d in $(seq 1 $n) ; do
		# subdirs
		for s in $(seq 1 $n) ; do
			# create subdirectory
			mkdir -p "$src/dir $d/subdir $d$s" || return

			# files
			for f in $(seq 1 $n) ; do
				echo "dir $d/subdir $d$s/file $d$s$f" > "$src/dir $d/subdir $d$s/file $d$s$f"
			done
		done
	done

	# create backup & config path
	mkdir -p tests/files/backups tests/files/config || return

	# import config
	cp tests/config/$1/*.conf tests/files/config/ || return

	# set the src folder as source to backup
	echo tests/files/src > tests/files/config/sources.conf
}


t2b_history() {
	t2b history "$test_file"
}


t2b_restore() {
	# delete file
	rm -f "$test_file" || return

	t2b restore --force --latest "$test_file" || return

	# check if file exists again
	[ -f "$test_file" ]
}
