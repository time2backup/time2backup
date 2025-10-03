#
#  time2backup rsync functions
#
#  Index
#
#   prepare_cmd
#   get_rsync_remote_command
#   cmd_result
#


# Prepare rsync command and arguments in the $backup_cmd variable
# Usage: prepare_cmd COMMAND
# Dependencies: $backup_cmd, $rsync_path, $quiet_mode, $files_progress,
#               $preserve_permissions, $config_includes, $config_excludes, $rsync_options, $max_size
prepare_cmd() {
	# basic command
	backup_cmd=("$rsync_path" -rltDH)

	# options depending on configuration

	if ! lb_istrue $quiet_mode ; then
		backup_cmd+=(-v)
		
		if lb_istrue $files_progress ; then
			backup_cmd+=(--progress)
		else
			# show global progress (works with rsync > 3.1.0)
			if lb_compare_versions $("$rsync_path" -V 2> /dev/null | grep -Eo "[0-9]+\.[0-9]+\.[0-9]+") -ge 3.1.0 ; then
				backup_cmd+=("--info=progress2")
			fi
		fi
	fi

	# test mode
	lb_istrue $test_mode && backup_cmd+=(--dry-run)

	# remote rsync path
	if lb_istrue $remote_source ; then
		local rsync_remote_command=$(get_rsync_remote_command)
		[ -n "$rsync_remote_command" ] && backup_cmd+=(--rsync-path "$rsync_remote_command")
	fi

	case $1 in
		import|export)
			# force preserve permissions
			backup_cmd+=(-pog)
			;;

		*)
			# preserve permissions
			lb_istrue $preserve_permissions && backup_cmd+=(-pog)

			# includes & excludes
			[ -f "$config_includes" ] && backup_cmd+=(--include-from "$config_includes")
			[ -f "$config_excludes" ] && backup_cmd+=(--exclude-from "$config_excludes")

			# user defined options
			[ ${#rsync_options[@]} -gt 0 ] && backup_cmd+=("${rsync_options[@]}")
			;;
	esac

	# command-specific options
	case $1 in
		backup)
			# delete newer files
			backup_cmd+=(--delete)

			# add max size if specified
			[ -n "$max_size" ] && backup_cmd+=(--max-size "$max_size")
			;;
	esac
}


# Generate rsync remote command
# Usage: get_rsync_remote_command
# Dependencies: $rsync_remote_path
# Return: Remote command
get_rsync_remote_command() {
	# return custom rsync remote path if defined
	[ -z "$rsync_remote_path" ] || echo "$rsync_remote_path"
}


# Manage rsync exit codes
# Usage: cmd_result EXIT_CODE
# Exit codes:
#   0: rsync was OK
#   1: usage error
#   2: rsync error
cmd_result() {
	lb_is_integer $1 || return 1

	case $1 in
		0|23|24)
			# OK or partial transfer
			return 0
			;;
		*)
			# critical errors that caused backup to fail
			return 2
			;;
	esac
}
