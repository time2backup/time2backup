#
#  time2backup commands
#
#  This file is part of time2backup (https://time2backup.org)
#
#  MIT License
#  Copyright (c) 2017-2021 Jean Prunneaux
#

# Index
#
#   Commands
#     t2b_backup
#     t2b_restore
#     t2b_history
#     t2b_explore
#     t2b_config
#     t2b_mv
#     t2b_clean
#     t2b_rotate
#     t2b_status
#     t2b_stop
#     t2b_import
#     t2b_export
#     t2b_install
#     t2b_uninstall


# Perform backup
# Usage: t2b_backup [OPTIONS] [PATH...]
t2b_backup() {
	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-p|--progress)
				files_progress=true
				;;
			-c|--comment)
				backup_comment=$(lb_getopt "$@")
				if [ $? != 0 ] ; then
					print_help
					return 1
				fi
				shift
				;;
			--resume)
				resume_last=true
				;;
			-u|--unmount)
				unmount=true
				;;
			-s|--shutdown)
				shutdown=true
				;;
			-r|--recurrent)
				recurrent_backup=true
				;;
			-t|--test)
				test_mode=true
				test_destination=false
				debug "Test mode"
				;;
			--force-unlock)
				force_unlock=true
				;;
			-q|--quiet)
				quiet_mode=true
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	local sources=()

	# set specified source(s)
	if [ $# -gt 0 ] ; then
		sources=("$@")
	else
		# if sources not specified, get them from config file
		if ! lb_read_config "$config_sources" ; then
			lbg_error "Cannot read sources.conf file!"
			clean_exit 3
		fi

		sources=("${lb_read_config[@]}")
	fi

	# if no sources to backup, exit
	if [ ${#sources[@]} = 0 ] ; then
		lbg_warning "$tr_nothing_to_backup\n$tr_please_configure_sources"
		clean_exit 4
	fi

	# get current date
	current_date=$(lb_timestamp2date -f '%Y-%m-%d at %H:%M:%S' $current_timestamp)

	# set backup directory with current date (format: YYYY-MM-DD-HHMMSS)
	backup_date=$(lb_timestamp2date -f '%Y-%m-%d-%H%M%S' $current_timestamp)

	# get last backup file
	last_backup_file=$config_directory/.lastbackup

	# if file does not exist, create it
	touch "$last_backup_file" || \
		lb_warning "Cannot create last backup file! Verify your right access on config directory."

	# get last backup timestamp
	last_backup_timestamp=$(cat "$last_backup_file" 2> /dev/null | grep -Eo "^[1-9][0-9]*$")

	# if recurrent, check frequency
	if lb_istrue $recurrent_backup ; then

		# if disabled in default configuration
		if ! lb_istrue $enable_recurrent ; then
			lb_display_error "Recurrent backups are disabled."
			clean_exit 20
		fi

		# recurrent backups not enabled in configuration
		if ! lb_istrue $recurrent ; then
			lb_warning "Recurrent backups are disabled. You can enable it in configuration file."
			clean_exit 20
		fi

		# if cannot get last timestamp, cancel (avoid to backup every minute)
		if ! [ -w "$last_backup_file" ] ; then
			lb_display_error "Cannot get/save the last backup timestamp."
			clean_exit 21
		fi

		# compare timestamps
		if [ -n "$last_backup_timestamp" ] ; then
			# convert frequency in seconds
			case $frequency in
				hourly)
					frequency=1h
					;;
				""|daily)
					frequency=1d
					;;
				weekly)
					frequency=7d
					;;
				monthly)
					frequency=31d
					;;
			esac

			# convert to seconds offset
			seconds_offset=$(period2seconds $frequency)

			# test if delay is passed
			test_timestamp=$(($current_timestamp - $last_backup_timestamp))

			if [ $test_timestamp -gt 0 ] ; then
				if [ $test_timestamp -le $seconds_offset ] ; then
					debug "Last backup was done at $(lb_timestamp2date -f "$tr_readable_date" $last_backup_timestamp), we are now $(lb_timestamp2date -f "$tr_readable_date" $current_timestamp) (backup every $(($seconds_offset / 60)) minutes)"
					lb_info "Recurrent backup: no need to backup."

					# exit without email or shutdown or delete log (does not exists)
					return 0
				fi
			else
				lb_display_critical "Last backup is more recent than today. Are you a time traveller?"
			fi
		fi
	fi # recurrent backups

	# execute before backup command/script
	run_before

	# prepare destination (mount and verify writable)
	prepare_destination
	case $? in
		1)
			# destination not reachable: display error if not recurrent backup
			lb_istrue $recurrent_backup || lbg_error "$tr_backup_unreachable\n$tr_verify_media"
			return 6
			;;
		2)
			# destination not writable
			return 7
			;;
	esac

	# test if a backup is running
	local existing_lock=$(current_lock)
	if [ -n "$existing_lock" ] ; then

		debug "Lock found: $existing_lock"

		# force mode: delete old lock
		if lb_istrue $force_unlock ; then
			lb_info "Force mode: deleting lock $existing_lock"
			release_lock -f || clean_exit 8
		else
			# print error message
			lb_display_error "$tr_backup_already_running"

			# display window error
			if ! lb_istrue $recurrent_backup && ! lb_istrue $console_mode ; then
				lbg_error "$tr_backup_already_running"
			fi
			clean_exit 8
		fi
	fi

	# catch term signals
	catch_kills cancel_exit

	create_lock

	# set log file path
	logfile=$logs_directory/time2backup_$backup_date.log

	# create log file and exit if error
	create_logfile "$logfile" || clean_exit 9

	lb_display --log "Backup started on $current_date\n"
	notify "$tr_notify_prepare_backup"
	lb_display --log "Prepare backup destination..."

	# force set to false to print in infofile
	lb_istrue $hard_links || hard_links=false
	lb_istrue $recurrent_backup || recurrent_backup=false

	# prepare rsync command
	prepare_rsync backup

	create_infofile

	# prepare results
	success=() warnings=() errors=()

	# execute backup for each source
	# do a loop like this to prevent errors with spaces in strings
	# do not use for ... in ... syntax
	for ((s=0; s < ${#sources[@]}; s++)) ; do

		# reset variables
		cmd=("${rsync_cmd[@]}")
		src=${sources[s]}
		total_size=""
		estimated_time=""
		remote_source=false
		last_clean_backup=""

		lb_display --log "\n********************************************\n"
		lb_display --log "Backup $src... ($(($s + 1))/${#sources[@]})\n"
		lb_display --log "Preparing backup..."

		# save current timestamp
		src_timestamp=$(date +%s)

		# get source path
		case $(get_protocol "$src") in
			ssh)
				# test if we don't have double remotes
				# (rsync does not support ssh to ssh copy)
				if lb_istrue $remote_destination ; then
					lb_display_error --log "You cannot backup a remote path to a remote destination."
					errors+=("$src (cannot backup a remote path on a remote destination)")
					lb_exitcode=3
					continue
				fi

				remote_source=true

				if lb_istrue $clone_mode ; then
					path_dest=$(basename "$src")
				else
					# get full backup path
					path_dest=$(get_backup_path "$src")
				fi

				# set absolute source path
				abs_src=$(url2ssh "$src")
				;;

			*)
				# file or directory

				# replace ~ by user home directory
				if [ "${src:0:1}" = "~" ] ; then
					# get first part of the path
					homealias=$(echo "$src" | awk -F '/' '{ print $1 }')

					# get user homepath
					if [ "$homealias" = "~" ] ; then
						homedir=$(lb_homepath)
					else
						# defined user (e.g. ~other)
						homedir=$(lb_homepath "${homealias:1}")
					fi

					# the Windows case
					# Be careful, ~other won't work on Windows systems
					[ "$lb_current_os" = Windows ] && homedir=$(cygpath "$USERPROFILE")

					# test if path exists
					if ! [ -d "$homedir" ] ; then
						lb_display_error --log "Cannot get user homepath.\nPlease use absolute paths instead of ~ aliases in your sources.conf file."
						errors+=("$src (does not exists)")
						lb_exitcode=10

						# continue to next source
						continue
					fi

					# get the real homepath (it's important if homepath is a symlink)
					src=$(lb_realpath "$homedir")/$(echo "$src" | sed 's/^[^/]*\///')
				fi

				# get UNIX format for Windows paths
				[ "$lb_current_os" = Windows ] && src=$(cygpath "$src")

				# get absolute path for source
				abs_src=$(lb_abspath "$src")

				# test if source exists
				if ! [ -e "$abs_src" ] ; then
					lb_error --log "Source $src does not exists!"
					errors+=("$src (does not exists)")
					lb_exitcode=10

					# continue to next source
					continue
				fi

				if lb_istrue $clone_mode ; then
					path_dest=$(basename "$abs_src")
				else
					# get backup path
					path_dest=$(get_backup_path "$abs_src")
				fi
				;;
		esac

		# of course, we exclude the backup destination itself if it is included
		# into the backup source
		# e.g. to backup /media directory, we must exclude /user/device/path/to/backups
		exclude_backup_dir=$(auto_exclude "$abs_src")
		if [ $? != 0 ] ; then
			errors+=("$src (exclude error)")
			lb_exitcode=11

			# continue to next source
			continue
		fi

		# if there is something to exclude, do it
		[ -n "$exclude_backup_dir" ] && cmd+=(--exclude "$exclude_backup_dir")

		# search in source if exclude conf file is set
		[ -f "$abs_src"/.rsyncignore ] && cmd+=(--exclude-from "$abs_src"/.rsyncignore)

		# remote options
		if lb_istrue $remote_source || lb_istrue $remote_destination ; then
			# enables network compression
			lb_istrue $network_compression && cmd+=(-z)

			# add ssh options
			[ "${#ssh_options[@]}" -gt 0 ] && cmd+=(-e "ssh ${ssh_options[*]}")
		fi

		# set rsync remote path for remote sources
		if lb_istrue $remote_source ; then
			local rsync_remote_command=$(get_rsync_remote_command)
			[ -n "$rsync_remote_command" ] && cmd+=(--rsync-path "$rsync_remote_command")
		fi

		# if it is a directory, add '/' at the end of the path
		if [ -d "$abs_src" ] ; then
			[ "${abs_src:${#abs_src}-1}" != / ] && abs_src+=/
		fi

		# write new source section to info file
		lb_set_config -s src$(($s + 1)) "$infofile" path "$src"
		lb_set_config -s src$(($s + 1)) "$infofile" rsync_result -1

		if lb_istrue $remote_destination ; then
			# prepare remote backup
			local remote_opts=()
			lb_istrue $force_unlock && remote_opts+=(--unlock)

			if lb_istrue $resume_last ; then
				debug "Resume from last backup"
				remote_opts+=(--resume)
			fi

			# add server path (with token provided)
			prepare_remote_destination backup "${remote_opts[@]}" $backup_date "$src" && \
				cmd+=(--rsync-path "$(get_rsync_remote_command) backup --t2b-rotate $keep_limit --t2b-keep $clean_keep $(! lb_istrue $trash_mode || echo --t2b-trash)")
		else
			# prepare backup folder
			prepare_backup
		fi

		# if prepare destination failed,
		if [ $? != 0 ] ; then
			lb_display_error --log "Could not prepare backup destination for source $src. Please verify your access rights."

			# prepare report and save exit code
			errors+=("$src (write error)")
			[ $lb_exitcode = 0 ] && lb_exitcode=7

			# clean directory but NOT the infofile
			clean_empty_backup $backup_date "$path_dest"

			# continue to next source
			continue
		fi

		# If keep_limit = 0 (mirror mode), we don't need to use versionning.
		# If first backup, no need to add incremental options.
		if [ $keep_limit != 0 ] && [ -n "$last_clean_backup" ] ; then

			# write trash in infofile
			lb_set_config -s src$(($s + 1)) "$infofile" trash $last_clean_backup

			# if destination supports hard links, use incremental with hard links system
			if lb_istrue $hard_links ; then

				debug "Last backup used for link dest: $last_clean_backup"

				# get link relative path (../../...)
				local linkdest=$(get_relative_path "$destination/$backup_date/$path_dest" "$destination")

				if [ -n "$linkdest" ] ; then
					linkdest+=$last_clean_backup

					if lb_istrue $remote_destination ; then
						# the case of spaces in remote path
						linkdest+=$(echo "$path_dest" | sed 's/ /\\ /g')
					else
						linkdest+=$path_dest
					fi

					cmd+=(--link-dest "$linkdest")
				fi
			else
				# no hard links
				debug "Last backup used for trash: $last_clean_backup"

				# last backup folder will contains only changed/deleted files
				prepare_trash || continue

				# set trash path
				# Note: use absolute path to avoid trash to be inside backup destination
				#       if destination variable is a relative path
				cmd+=(-b --backup-dir "$trash")
			fi
		fi

		# trash mode
		if lb_istrue $trash_mode ; then
			# "trash" folder that contains older revisions
			prepare_trash || continue

			# set trash path (old files will be suffixed by _DATE)
			# Note: use absolute path to avoid trash to be inside backup destination
			#       if destination variable is a relative path
			cmd+=(-b --backup-dir "$trash" --suffix "_$backup_date")
		fi

		# add source
		cmd+=("$abs_src")

		# add destination
		if lb_istrue $clone_mode ; then
			# one source or source is a file: clone to destination
			if [ ${#sources[@]} = 1 ] || [ "${abs_src:${#abs_src}-1}" != / ] ; then
				cmd+=("$(url2ssh "$destination")")
			else
				# multiple sources: clone to destination/directory
				cmd+=("$(url2ssh "$destination/$path_dest")")
			fi
		else
			cmd+=("$(url2ssh "$destination/$backup_date/$path_dest")")
		fi

		# prepare backup: testing space
		if lb_istrue $test_destination ; then

			# test rsync and space available for backup
			if ! test_backup "${cmd[@]}" ; then
				lb_display --log "Error in rsync test."

				# prepare report and save exit code
				errors+=("$src (rsync test error)")
				[ $lb_exitcode = 0 ] && lb_exitcode=12

				# clean directory but NOT the infofile
				clean_empty_backup $backup_date "$path_dest"

				# continue to the next backup source
				continue
			fi

			debug "Backup total size (in bytes): $total_size"

			# write size in infofile
			lb_set_config -s src$(($s + 1)) "$infofile" size $total_size

			# if not enough space on disk to backup, cancel
			if ! free_space $total_size ; then
				lb_display_error --log "Not enough space on device to backup. Abording."

				# prepare report and save exit code
				errors+=("$src (not enough space left)")
				[ $lb_exitcode = 0 ] && lb_exitcode=13

				# clean directory but NOT the infofile
				clean_empty_backup $backup_date "$path_dest"

				# continue to next source
				continue
			fi
		fi # end of free space tests

		lb_display --log "\nRunning backup..."
		debug "Run ${cmd[*]}\n"

		# display start notification
		notification_started_backup=$tr_backup_in_progress
		# ... with nb/total if more than one source
		[ ${#sources[@]} -gt 1 ] && notification_started_backup+=" ($(($s + 1))/${#sources[@]})"

		# print estimated time
		estimated_time=$(estimate_backup_time "$src" $total_size)
		if [ -n "$estimated_time" ] ; then
			# convert into minutes
			estimated_time=$(($estimated_time / 60 + 1))

			info_estimated_time=$(printf "$tr_estimated_time" $estimated_time)

			# print estimated time in console
			lb_info "$info_estimated_time"
			echo

			notification_started_backup+="\n$info_estimated_time"
		fi

		# display start notification
		notify "$notification_started_backup"

		# real backup: execute rsync command, print result into terminal and logfile
		"${cmd[@]}" 2> >(tee -a "$logfile" >&2)

		# get backup result and prepare report
		res=${PIPESTATUS[0]}

		# save rsync result in info file and delete temporary file
		lb_set_config -s src$(($s + 1)) "$infofile" rsync_result $res

		if [ $res = 0 ] ; then
			# backup succeeded
			# (ignoring vanished files in transfer)
			success+=("$src")
		else
			# determine between warnings and errors
			if rsync_result $res ; then
				# rsync minor errors (partial transfers)
				warnings+=("$src (some files were not backed up; code: $res)")
				lb_exitcode=15
			else
				# critical errors that caused backup to fail
				errors+=("$src (backup failed; code: $res)")
				lb_exitcode=14
			fi
		fi

		if lb_istrue $trash_mode ; then
			clean_empty_backup trash "$path_dest"
		else
			# clean empty old backup and infofile
			clean_empty_backup -i $last_clean_backup "$path_dest"
		fi

		# write duration in infofile
		lb_set_config -s src$(($s + 1)) "$infofile" duration $(( $(date +%s) - $src_timestamp ))

		# clean directory WITHOUT infofile
		clean_empty_backup $backup_date "$path_dest"

	done # end of backup sources

	# if cancel, do not consider as cancelled backup
	catch_kills clean_exit

	lb_display --log "\n********************************************\n"

	# if nothing was backed up ($res variable has never been set),
	# consider it as a critical error and do not rotate backups
	if [ -z "$res" ] ; then
		errors+=("Nothing was backed up.")
		lb_exitcode=22
	fi

	if ! lb_istrue $remote_destination ; then
		if [ -d "$destination" ] ; then
			# final cleanup
			clean_empty_backup -i $backup_date
		else
			# if destination disappered (e.g. network folder disconnected),
			# return a critical error
			errors+=("Destination folder vanished! Disk or network may have been disconnected.")
			lb_exitcode=14
		fi
	fi

	case $lb_exitcode in
		# backup succeeded (all OK or warnings)
		0|5|15)
			# create latest backup directory link
			create_latest_link

			# save current timestamp into config/.lastbackup file
			date +%s > "$last_backup_file" || \
				lb_display_error --log "Failed to save backup date! Please check your access rights on the config directory or recurrent backups won't work."

			# rotate backups
			rotate_backups
			;;
	esac

	# print final report
	lb_display --log "Backup ended on $(date '+%Y-%m-%d at %H:%M:%S')"
	lb_display --log "$(report_duration)\n"

	if [ $lb_exitcode = 0 ] ; then
		lb_display --log "Backup finished successfully."
		notify_backup_end "$tr_backup_finished\n$(report_duration)"
	else
		lb_display --log "Backup finished with some errors. Check report below and see log files for more details.\n"

		if [ ${#success[@]} -gt 0 ] ; then
			report_details+="
Success:
"
			for i in "${success[@]}" ; do
				report_details+="   - $i
"
			done
		fi

		if [ ${#warnings[@]} -gt 0 ] ; then
			report_details+="
Warnings:
"
			for i in "${warnings[@]}" ; do
				report_details+="   - $i
"
			done

			# do not display warning message if there are critical errors to display after that
			if [ ${#errors[@]} = 0 ] ; then
				notify_backup_end "$tr_backup_finished_warnings $tr_see_logfile_for_details\n$(report_duration)"
			fi
		fi

		if [ ${#errors[@]} -gt 0 ] ; then
			report_details+="
Errors:
"
			for i in "${errors[@]}" ; do
				report_details+="   - $i
"
			done

			notify_backup_end "$tr_backup_failed $tr_see_logfile_for_details\n$(report_duration)"
		fi

		lb_display --log "$report_details"
	fi

	# execute after backup command/script
	run_after

	clean_exit
}


# Restore a file
# Usage: t2b_restore [OPTIONS] [PATH] [DESTINATION]
t2b_restore() {
	# default option values
	backup_date=latest
	local choose_date=true force_mode=false directory_mode=false \
	      restore_moved=false delete_newer_files=false restore_path

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-d|--date)
				backup_date=$(lb_getopt "$@")
				if ! check_backup_date "$backup_date" ; then
					print_help
					return 1
				fi
				choose_date=false
				shift
				;;
			-l|--latest)
				backup_date=latest
				choose_date=false
				;;
			--delete-new)
				delete_newer_files=true
				;;
			-p|--progress)
				files_progress=true
				;;
			-t|--test)
				test_mode=true
				no_lock=true
				debug "Test mode"
				;;
			--no-lock)
				no_lock=true
				;;
			-f|--force)
				force_mode=true
				;;
			-q|--quiet)
				quiet_mode=true
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# test backup destination
	prepare_destination || return 4

	# get all backups
	if ! lb_istrue $remote_destination && ! lb_istrue $clone_mode ; then
		backups=($(get_backups))
		# if no backups, exit
		if [ ${#backups[@]} = 0 ] ; then
			lbg_error "$tr_no_backups_available"
			return 5
		fi
	fi

	# get path from argument
	local file choose_destination=false

	# clone mode: force to choose restore destination
	lb_istrue $clone_mode && choose_destination=true

	# if path is specified:
	if [ ${#1} -gt 0 ] ; then
		if [ "$(get_protocol "$1")" = ssh ] ; then
			file=$1
		else
			# get it in absolute path
			file=$(lb_abspath -n "$1")

			if [ ${#file} = 0 ] ; then
				lb_error "File does not exist."
				lb_error "If you want to restore a deleted file, please specify an absolute path."
				return 1
			fi
		fi
	else
		# if no path specified, go to interactive mode

		# choose type of file to restore (file/directory)
		local choices=("$tr_restore_existing_file" "$tr_restore_existing_directory")

		if ! lb_istrue $remote_destination && ! lb_istrue $clone_mode ; then
			choices+=("$tr_restore_moved_file" "$tr_restore_moved_directory")
		fi

		lbg_choose_option -d 1 -l "$tr_choose_restore" "${choices[@]}" || return 0

		# manage chosen option
		case $lbg_choose_option in
			1)
				# restore a file
				;;
			2)
				# restore a directory
				directory_mode=true
				;;
			3)
				# restore a moved file
				starting_path=$destination
				restore_moved=true
				;;
			4)
				# restore a moved directory
				starting_path=$destination
				directory_mode=true
				restore_moved=true
				;;
			*)
				return 1
				;;
		esac

		# choose a directory to restore (return absolute path)
		if $directory_mode ; then
			lbg_choose_directory -t "$tr_choose_directory_to_restore" -a "$starting_path" || return 0
			file=$lbg_choose_directory
		else
			# choose a file to restore (return absolute path)
			lbg_choose_file -t "$tr_choose_file_to_restore" -a "$starting_path" || return 0
			file=$lbg_choose_file
		fi

		# restore a moved/deleted file
		if $restore_moved ; then
			# test if path to restore is stored in the backup directory
			if [[ "$file" != "$destination"* ]] ; then
				lbg_error "$tr_path_is_not_backup"
				return 1
			fi

			# remove destination path prefix
			file=${file#$destination}
			# remove first slash
			[ "${file:0:1}" = / ] && file=${file:1}

			# get backup date
			backup_date=$(echo $file | grep -o "^$backup_date_format")
			if [ -z "$backup_date" ] ; then
				lbg_error "$tr_path_is_not_backup"
				return 1
			fi

			choose_date=false

			# remove backup date path prefix
			file=${file#$backup_date}

			# check if it is a file backup
			case $(echo ${file:0:7}) in
				/files/)
					# absolute path of destination
					file=${file:6}
					;;
				/ssh/*)
					# transform path to URL
					# Warning: if user@host defined, it will be lost (keep only host)
					file=ssh:/${file:4}
					;;
				*)
					lbg_error "$tr_path_is_not_backup"
					return 1
					;;
			esac

			# TODO: translate
			lbg_yesno "Do you want to choose a place to restore your files?" && choose_destination=true
		fi
	fi

	# test if path to restore is stored in the backup directory
	if lb_istrue $clone_mode && [[ "$file" != "$destination"* ]] ; then
		debug "Bad path to restore: $file"
		lbg_error "$tr_path_is_not_backup"
		return 1
	fi

	# specified restore destination path
	if [ -n "$2" ] ; then
		debug "Restore path destination: $2"
		restore_path=$2
	else
		if $choose_destination ; then
			# choose destination folder
			lbg_choose_directory -t "Choose a destination:" || return 0
			restore_path=$lbg_choose_directory
		else
			# restore at original path
			restore_path=$file
		fi
	fi

	# remote path
	if [ "$(get_protocol "$restore_path")" = ssh ] ; then
		# test if we don't have double remotes
		# (rsync does not support ssh to ssh copy)
		if lb_istrue $remote_destination ; then
			lbg_display_error "You cannot restore a remote backup to a remote destination."
			return 1
		fi
		remote_source=true
	else
		# get UNIX format for Windows paths
		if [ "$lb_current_os" = Windows ] ; then
			file=$(cygpath "$file")
			restore_path=$(cygpath "$restore_path")
	 	fi

		# detect directory mode if path ends with / (useful for deleted directories)
		[ "${file:${#file}-1}" = / ] && directory_mode=true
	fi

	debug "Source to restore: $file"

	# case of symbolic links
	if [ -L "$file" ] ; then
		lbg_error "$tr_cannot_restore_links"
		return 12
	fi

	if lb_istrue $clone_mode ; then
		src=$file
	else
		# get backup full path
		backup_file_path=$(get_backup_path "$file")

		# if error, exit
		[ -z "$backup_file_path" ] && return 1

		if lb_istrue $remote_destination ; then
			# remote: get backup versions of the file
			# be careful to send absolute path of the file and not $file that could be relative!
			file_history=($("${t2bserver_cmd[@]}" history "${backup_file_path:6}"))
			if [ $? != 0 ] ; then
				lb_error "Remote server connection error"
				return 4
			fi
		else
			# get backup versions of the file
			file_history=($(get_backup_history "$file"))
		fi

		# if no backup found
		if [ ${#file_history[@]} = 0 ] ; then
			lbg_error "$tr_no_backups_for_file"
			return 6
		fi

		# search for dates
		if [ "$backup_date" != latest ] ; then
			# if date was specified but not here, error
			if ! lb_in_array "$backup_date" "${file_history[@]}" ; then
				lbg_error "$tr_no_backups_on_date\n$tr_run_to_show_history $lb_current_script history $file"
				return 7
			fi
		fi

		# if interactive mode and more than 1 backup,
		# prompt user to choose a backup date
		if $choose_date && [ ${#file_history[@]} -gt 1 ] ; then

			# change dates to a user-friendly format
			history_dates=(${file_history[@]})

			for ((i=0; i<${#file_history[@]}; i++)) ; do
				history_dates[i]=$(get_backup_date "${file_history[i]}")
			done

			# choose backup date
			lbg_choose_option -d 1 -l "$tr_choose_backup_date" "${history_dates[@]}" || return 0

			# get chosen backup (= chosen ID - 1 because array ID starts from 0)
			backup_date=${file_history[lbg_choose_option-1]}
		fi

		# if latest backup wanted, get most recent date
		[ "$backup_date" = latest ] && backup_date=${file_history[0]}

		# remote: get infos from server
		# be careful to send absolute path of the file and not $file that could be relative!
		if lb_istrue $remote_destination ; then
			prepare_remote_destination restore $backup_date "${backup_file_path:6}" || return 4
		fi

		# test if a backup is running
		if ! lb_istrue $no_lock ; then
			if lb_istrue $remote_destination ; then
				[ "$server_status" = running ]
			else
				current_lock -q
			fi

			if [ $? = 0 ] ; then
				debug "Destination locked"

				# display window error & quit
				lbg_error "$tr_backup_already_running"
				return 4
			fi
		fi

		# set backup source for restore command
		src=$(url2ssh "$destination/$backup_date/$backup_file_path")
	fi # end of no clone mode

	# if source is a directory (or if t2b server told us so)
	if [ -d "$src" ] || [ "$src_type" = directory ] ; then
		local warn_partial=false

		# no hard links: warn when restoring old directories
		if ! lb_istrue $hard_links && [ "$backup_date" != "${file_history[0]}" ] ; then
			warn_partial=true
		fi

		# if rsync result was not good (backup failed or was incomplete)
		if ! lb_istrue $remote_destination && ! lb_istrue $clone_mode ; then
			rsync_result=$(get_infofile_value "$destination/$backup_date/backup.info" "$file" rsync_result)
			[ "$rsync_result" != 0 ] && warn_partial=true
		fi

		# warn user & ask to confirm
		if $warn_partial ; then
			lb_istrue $console_mode || lb_warning "$tr_warn_restore_partial"
			lbg_yesno "$tr_warn_restore_partial\n$tr_confirm_restore_2" || return 0
		fi

		# add mandatory / at the end of path
		[ "${src:${#src}-1}" != / ] && src+=/

		# enable directory mode
		directory_mode=true
	fi

	# prepare destination path
	case $(get_protocol "$restore_path") in
		ssh)
			dest=$(url2ssh "$restore_path")
			;;
		*)
			dest=$restore_path
			;;
	esac

	debug "Restore destination: $dest"

	# prepare rsync command
	prepare_rsync restore

	# of course, we exclude the backup destination itself if it is included
	# into the destination path
	# e.g. to restore /media directory, we must exclude /user/device/path/to/backups
	exclude_backup_dir=$(auto_exclude "$dest")
	if [ $? = 0 ] ; then
		# if there is something to exclude, do it
		[ -n "$exclude_backup_dir" ] && rsync_cmd+=(--exclude "$exclude_backup_dir")
	else
		lbg_error "$tr_restore_unknown_error"
		return 8
	fi

	# search in source if exclude conf file is set
	[ -f "$src"/.rsyncignore ] && rsync_cmd+=(--exclude-from "$src"/.rsyncignore)

	# test newer files
	if ! $delete_newer_files ; then
		if $directory_mode ; then
			# prepare test command
			cmd=("${rsync_cmd[@]}")
			cmd+=(--delete --dry-run "$src" "$dest")

			notify "$tr_notify_prepare_restore"
			lb_display --log "Preparing restore..."
			debug "Run ${cmd[*]}"

			# test rsync to check newer files
			if "${cmd[@]}" | grep -q "^deleting " ; then
				# ask to keep new files
				lbg_yesno "$tr_ask_keep_newer_files_1\n$tr_ask_keep_newer_files_2" || delete_newer_files=true
			fi
		else
			# if restore a file, always delete new
			delete_newer_files=true
		fi
	fi

	# confirm restore
	if ! $force_mode ; then
		if ! lbg_yesno "$(printf "$tr_confirm_restore_1" "$file" "$(get_backup_date $backup_date)")\n$tr_confirm_restore_2" ; then
			notify "$tr_restore_cancelled"
			return 0
		fi
	fi

	# prepare rsync restore command
	cmd=("${rsync_cmd[@]}")

	# delete new files
	$delete_newer_files && cmd+=(--delete)

	# remote server
	lb_istrue $remote_destination && \
		cmd+=(--rsync-path "$(get_rsync_remote_command) restore $(lb_istrue $no_lock && echo --t2b-nolock)")

	cmd+=("$src" "$dest")

	# catch term signals
	catch_kills cancel_exit

	if ! lb_istrue $no_lock ; then
		# retest if a backup is running
		if lb_istrue $remote_destination ; then
			[ "$server_status" = running ]
		else
			current_lock -q
		fi

		if [ $? = 0 ] ; then
			debug "Destination locked"

			# display window error & quit
			lbg_error "$tr_backup_already_running"
			return 4
		else
			# create lock
			create_lock
		fi
	fi

	# set log file path
	logfile=$logs_directory/restore_$(date '+%Y-%m-%d-%H%M%S').log

	# create log file for errors
	create_logfile "$logfile" || \
		lb_warning "Cannot create log file. If there are errors, you will not be able to check them easely."

	notify "$tr_notify_restoring"
	lb_display --log "Restore $(lb_abspath "$dest") from backup $backup_date...\n"
	debug "Run ${cmd[*]}\n"

	local res=0

	# create parent directory if not exists
	case $(get_protocol "$restore_path") in
		ssh)
			# do nothing
			;;
		*)
			mkdir -p "$(dirname "$dest")"
			res=$?
			;;
	esac

	# execute rsync command, print result into terminal and errors in logfile
	[ $res = 0 ] && \
	"${cmd[@]}" 2> >(tee -a "$logfile" >&2)
	lb_result --log
	res=$?

	# if no errors,
	if [ $res = 0 ] ; then
		# delete log file, print info and quit
		delete_logfile
		lbg_info "$tr_restore_finished"
		clean_exit 0
	fi

	# if the was errors,
	if rsync_result $res ; then
		# rsync minor errors (partial transfers)
		lbg_warning "$tr_restore_finished_warnings"
		res=10
	else
		# rsync critical error: open logfile and print message
		if [ -r "$logfile" ] ; then
			open_config "$logfile" &> /dev/null &
		fi
		lbg_error "$tr_restore_failed"
		res=9
	fi

	# open logfile if exists and is readable
	if [ -e "$logfile" ] && [ -r "$logfile" ] ; then
		open_config "$logfile" &> /dev/null &
	fi

	clean_exit $res
}


# Get history/versions of a file
# Usage: t2b_history [OPTIONS] PATH
t2b_history() {
	if lb_istrue $clone_mode ; then
		echo "This command is disabled in clone mode."
		return 255
	fi

	# default option values
	local history_opts=() file abs_file

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-a|--all)
				history_opts=(-a)
				;;
			-q|--quiet)
				quiet_mode=true
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# missing arguments
	if [ $# = 0 ] ; then
		print_help
		return 1
	fi

	# get path
	if [ "$lb_current_os" = Windows ] ; then
		# get UNIX format for Windows paths
		file=$(cygpath "$*")
	else
		file=$*
	fi

	# get absolute path (if failed, ignore error)
	abs_file=$(lb_abspath "$file")
	[ -n "$abs_file" ] && file=$abs_file

	if lb_istrue $remote_destination ; then
		# remote: get backup versions of the file
		file_history=($("${t2bserver_cmd[@]}" history "${history_opts[@]}" "$file"))
		if [ $? != 0 ] ; then
			lb_error "Remote server connection error"
			return 4
		fi
	else
		# local: test backup destination
		prepare_destination || return 4

		# get backup versions of the file
		file_history=($(get_backup_history "${history_opts[@]}" "$file"))
	fi

	# no backup found
	if [ ${#file_history[@]} = 0 ] ; then
		lb_error "No backup found for '$file'!"
		return 5
	fi

	# print backup versions
	for b in "${file_history[@]}" ; do
		# quiet mode or remote destination: just print the version
		if lb_istrue $quiet_mode || lb_istrue $remote_destination ; then
			echo "$b"
		else
			# complete result: print details
			abs_file=$(get_backup_path "$file")
			[ -z "$abs_file" ] && continue

			backup_file=$destination/$b/$abs_file

			echo

			# get number of files
			nb_files=$(ls -l "$backup_file" 2> /dev/null | wc -l)

			if [ -n "$nb_files" ] ; then
				if [ $nb_files -gt 1 ] ; then
					nb_files=$(($nb_files - 1))
					echo "$b: $nb_files file(s)"
				else
					echo "$b: $nb_files file"
				fi
			fi

			# print details of file/directory
			echo "$(cd "$(dirname "$backup_file")" && ls -ld "$(basename "$backup_file")" 2> /dev/null)"
		fi
	done

	# complete result (not quiet mode)
	if ! lb_istrue $quiet_mode ; then
		echo
		echo "${#file_history[@]} backups found for $file"
	fi

	return 0
}


# Explore backups
# Usage: t2b_explore [OPTIONS] [PATH]
t2b_explore() {
	if lb_istrue $remote_destination ; then
		echo "This command is disabled for remote destinations."
		return 255
	fi

	if lb_istrue $console_mode ; then
		echo "This command is not available in console mode."
		return 255
	fi

	# default options
	backup_date=""
	local explore_all=false

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-d|--date)
				backup_date=$(lb_getopt "$@")
				if ! check_backup_date "$backup_date" ; then
					print_help
					return 1
				fi
				shift
				;;
			-l|--latest)
				backup_date=latest
				;;
			-a|--all)
				explore_all=true
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	path=$*

	# if path specified, test it
	if [ -n "$path" ] ; then
		if ! [ -e "$path" ] ; then
			print_help
			return 1
		fi
	fi

	# test backup destination
	prepare_destination || return 4

	# if path is not specified or in clone mode, open the backup destination folder
	if [ -z "$path" ] || lb_istrue $clone_mode ; then
		echo "Exploring backups..."

		if lbg_open_directory "$destination" ; then
			return 0
		else
			return 8
		fi
	fi

	# get all backups
	backups=($(get_backups))
	# if no backups, exit
	if [ ${#backups[@]} = 0 ] ; then
		lbg_error "$tr_no_backups_available"
		return 5
	fi

	# get backup full path
	backup_path=$(get_backup_path "$path")

	# if error, exit
	if [ -z "$backup_path" ] ; then
		print_help
		return 1
	fi

	# get all versions of the file/directory
	path_history=($(get_backup_history "$path"))

	# if no backup found
	if [ ${#path_history[@]} = 0 ] ; then
		lbg_error "$tr_no_backups_for_file"
		return 6
	fi

	# if backup date is specified,
	if [ -n "$backup_date" ] ; then
		# get the latest one
		if [ "$backup_date" = latest ] ; then
			backup_date=${path_history[0]}
		else
			# test if specified date exists
			if ! lb_in_array "$backup_date" "${path_history[@]}" ; then
				lbg_error "$tr_no_backups_on_date\n$tr_run_to_show_history $lb_current_script history $path"
				return 7
			fi
		fi

	else
		# explore all backups
		if $explore_all ; then
			# warn user if displaying many folders
			if [ ${#path_history[@]} -ge 10 ] ; then
				lbg_yesno "Warning: You are about to open ${#path_history[@]} windows! Are you sure to continue?" || return 0
			fi
			backup_date=${path_history[@]}

		else
			# if only one backup, no need to choose one
			if [ ${#path_history[@]} = 1 ] ; then
				backup_date=${path_history[0]}
			else
				# prompt user to choose a backup date

				# change dates to a user-friendly format
				history_dates=(${path_history[@]})

				for ((i=0; i<${#path_history[@]}; i++)) ; do
					history_dates[i]=$(get_backup_date "${path_history[i]}")
				done

				# choose backup date
				lbg_choose_option -d 1 -l "$tr_choose_backup_date" "${history_dates[@]}" || return 0

				# get chosen backup (= chosen ID - 1 because array ID starts from 0)
				backup_date=${path_history[lbg_choose_option-1]}
			fi
		fi
	fi

	# not a directory: get parent
	[ -d "$path" ] || backup_path=$(dirname "$backup_path")

	for b in "${backup_date[@]}" ; do
		echo "Exploring backup $b..."
		lbg_open_directory "$destination/$b/$backup_path"
	done

	return 0
}


# Configure time2backup
# Usage: t2b_config [OPTIONS]
t2b_config() {
	# default options
	local file op_config cmd_opts=()

	# get options
	# following other options to open_config() function
	while [ $# -gt 0 ] ; do
		case $1 in
			-g|--general)
				file=$config_file
				;;
			-x|--excludes)
				file=$config_excludes
				;;
			-i|--includes)
				file=$config_includes
				;;
			-s|--sources)
				file=$config_sources
				;;
			-l|--show)
				op_config=show
				;;
			-t|--test)
				op_config=test
				;;
			-w|--wizard)
				op_config=wizard
				;;
			-r|--reset)
				op_config=reset
				;;
			-e|--editor)
				if [ -z "$(lb_getopt "$@")" ] ; then
					print_help
					return 1
				fi
				cmd_opts=(-e "$2")
				shift
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# if config file not defined, ask user to choose which file to edit
	if [ -z "$file" ] ; then

		if [ -z "$op_config" ] ; then
			lbg_choose_option -d 1 -l "$tr_choose_config_file" \
				"$tr_global_config" "$tr_sources_config" "$tr_excludes_config" \
				"$tr_includes_config" "$tr_run_config_wizard" "$tr_open_other_config" || return 0

			case $lbg_choose_option in
				1)
					file=$config_file
					;;
				2)
					file=$config_sources
					;;
				3)
					file=$config_excludes
					;;
				4)
					file=$config_includes
					;;
				5)
					op_config=wizard
					;;
				6)
					op_config=create
					;;
				*)
					# bad choice
					return 1
					;;
			esac
		fi
	fi

	# operations to do on config
	case $op_config in
		create)
			lbg_choose_directory -t "$tr_choose_config_directory"
			[ -d "$lbg_choose_directory" ] || return 0

			# get current global options
			cmd_opts=()
			lb_istrue $console_mode && cmd_opts+=(-C)
			lb_istrue $debug_mode && cmd_opts+=(-D)

			# clear bash & rerun time2backup
			clear 2> /dev/null
			"$lb_current_script" -u $user "${cmd_opts[@]}" -c "$lbg_choose_directory"
			exit
			;;

		wizard)
			# run config wizard
			config_wizard
			;;

		show)
			# if not set, file config is general config
			[ -z "$file" ] && file=$config_file

			# get sources is a special case to print list without comments
			# read sources.conf file line by line
			while read -r line ; do
				lb_is_comment $line || echo "$line"
			done < "$file"

			[ $? != 0 ] && return 5
			;;

		test)
			echo "Testing configuration..."
			load_config
			lb_result
			;;

		reset)
			# reset config file
			lb_yesno "$tr_confirm_reset_config" && \
				cat "$lb_current_script_directory"/config/time2backup.example.conf > "$config_file"
			;;

		*)
			# edit configuration
			echo "Opening configuration file..."
			open_config "${cmd_opts[@]}" "$file"

			# after config,
			case $? in
				0)
					# config ok: reload it
					load_config || return 3

					# apply crontab config
					apply_crontab_config || return 4
					;;
				3)
					# errors in config
					return 5
					;;
				4)
					return 6
					;;
				*)
					return 7
					;;
			esac
			;;
	esac

	# config is not OK
	[ $? != 0 ] && return 3
}


# Move backup files
# Usage: t2b_mv [OPTIONS] PATH
t2b_mv() {
	if lb_istrue $clone_mode ; then
		lb_error "This command is disabled in clone mode."
		return 255
	fi

	if lb_istrue $remote_destination ; then
		lb_error "This command is disabled for remote destinations."
		return 255
	fi

	# default options
	local mv_latest=false force_mode=false

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-l|--latest)
				mv_latest=true
				;;
			-f|--force)
				force_mode=true
				;;
			-q|--quiet)
				quiet_mode=true
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# usage errors
	if [ $# -lt 2 ] ; then
		print_help
		return 1
	fi

	# test backup destination
	prepare_destination || return 4

	src=$1
	abs_src=$1

	if [ "$(get_protocol "$src")" = files ] ; then
		# get UNIX format for Windows paths
		[ "$lb_current_os" = Windows ] && src=$(cygpath "$src")

		# get absolute path of source
		abs_src=$(lb_abspath "$src")
	fi

	dest=$2
	abs_dest=$2

	if [ "$(get_protocol "$dest")" = files ] ; then
		# get UNIX format for Windows paths
		[ "$lb_current_os" = Windows ] && dest=$(cygpath "$dest")

		# get absolute path of source
		abs_dest=$(lb_abspath "$dest")
	fi

	# get all backup versions of this path
	file_history=($(get_backup_history -a "$src"))

	# no backup found
	if [ ${#file_history[@]} = 0 ] ; then
		lb_error "No backup found for '$src'!"
		return 5
	fi

	# get backup path of the source
	path_src=$(get_backup_path "$src")
	if [ $? != 0 ] || [ -z "$path_src" ] ; then
		lb_error "Cannot determine the backup path of your source. Please retry with an absolute path."
		return 6
	fi

	# get backup path of the destination
	path_dest=$(get_backup_path "$dest")
	if [ $? != 0 ] || [ -z "$path_dest" ] ; then
		lb_error "Cannot determine the backup path of your destination. Please retry with an absolute path."
		return 6
	fi

	# confirm action
	if ! $force_mode ; then
		lb_istrue $quiet_mode || echo "You are about to move ${#file_history[@]} backups from '$1' to '$2'."

		# warn user if destination already exists
		[ -e "$destination/$file_history/$path_dest" ] && \
			lb_warning "Destination already exists! This action may erase files."

		lb_yesno "Do you want to continue?" || return 0
	fi

	local b infofile section result=0
	for b in "${file_history[@]}" ; do
		lb_istrue $quiet_mode || echo "Moving file(s) for backup $b..."

		mkdir -p "$(dirname "$destination/$b/$path_dest")" && \
		mv "$destination/$b/$path_src" "$destination/$b/$path_dest"
		if [ $? = 0 ] ; then
			# get the infofile
			infofile=$destination/$b/backup.info
			section=$(find_infofile_section "$infofile" "$abs_src")

			# if the moved source is a source itself, rename it
			if [ -n "$section" ] ; then
				[ "$(lb_get_config -s $section "$infofile" path)" = "$abs_src" ] && \
					lb_set_config -s $section "$infofile" path "$abs_dest"
			fi

		else
			# mv failed
			lb_istrue $quiet_mode || lb_result 1
			result=7
		fi

		# if mv only latest backup, quit
		$mv_latest && break
	done

	return $result
}


# Clean files in backups
# Usage: t2b_clean [OPTIONS] PATH
t2b_clean() {
	if lb_istrue $clone_mode ; then
		lb_error "This command is disabled in clone mode."
		return 255
	fi

	if lb_istrue $remote_destination ; then
		echo "This command is disabled for remote destinations."
		return 255
	fi

	# default options
	local keep=0 force_mode=false

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-l|--keep-latest)
				keep=1
				;;
			-k|--keep)
				keep=$(lb_getopt "$@")
				if ! lb_is_integer "$keep" || [ $keep -lt 1 ] ; then
					print_help
					return 1
				fi
				shift
				;;
			-f|--force)
				force_mode=true
				;;
			-q|--quiet)
				quiet_mode=true
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# missing arguments
	if [ $# = 0 ] ; then
		print_help
		return 1
	fi

	# test backup destination
	prepare_destination || return 4

	if [ "$lb_current_os" = Windows ] ; then
		# get UNIX format for Windows paths
		src=$(cygpath "$1")
	else
		src=$1
	fi

	# get all backup versions of this path
	file_history=($(get_backup_history -a "$src"))

	# no backup found
	if [ ${#file_history[@]} = 0 ] ; then
		lb_error "No backup found for '$src'!"
		return 5
	fi

	# get path of file
	path_src=$(get_backup_path "$src")
	if [ $? != 0 ] || [ -z "$path_src" ] ; then
		lb_error "Cannot determine the backup path of your source. Please retry with an absolute path."
		return 6
	fi

	lb_istrue $quiet_mode || echo "${#file_history[@]} backup(s) found for '$src'"

	if [ ${#file_history[@]} -le $keep ] ; then
		lb_istrue $quiet_mode || echo "Nothing to clean"
		return 0
	fi

	# confirm action
	$force_mode || lb_yesno "Proceed cleaning?" || return 0

	local b result=0
	for ((i=$keep; i<${#file_history[@]}; i++)) ; do

		b=${file_history[i]}

		lb_istrue $quiet_mode || echo "Deleting backup $b ($(($i + 1 - $keep))/$((${#file_history[@]} - $keep)))..."

		# delete file(s)
		if ! rm -rf "$destination/$b/$path_src" ; then
			lb_istrue $quiet_mode || lb_result 1
			result=7
		fi
	done

	return $result
}


# Rotate backups manually
# Usage: t2b_rotate [OPTIONS] [LIMIT]
t2b_rotate() {
	if lb_istrue $clone_mode ; then
		lb_error "This command is disabled in clone mode."
		return 255
	fi

	# default options
	local force_mode=false

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-t|--test)
				test_mode=true
				force_mode=true
				;;
			-f|--force)
				force_mode=true
				;;
			-q|--quiet)
				quiet_mode=true
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	local keep=$keep_limit

	# test if number or period has a valid syntax
	if [ $# -gt 0 ] ; then
		if lb_is_integer "$1" ; then
			if [ $1 -lt 0 ] ; then
				print_help
				return 1
			fi
		else
			if ! test_period "$1" ; then
				print_help
				return 2
			fi
		fi

		keep=$1
	fi

	# prepare backup destination
	prepare_destination || return 4

	lb_istrue $quiet_mode || echo "You are about to rotate to keep $keep backup versions."
	lb_istrue $force_mode || lb_yesno "Continue?" || return 0

	rotate_backups $keep || return 5
}


# Check if a backup is currently running
# Usage: t2b_status [OPTIONS]
t2b_status() {
	if lb_istrue $clone_mode ; then
		lb_error "This command is disabled in clone mode."
		return 255
	fi

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-q|--quiet)
				quiet_mode=true
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# test backup destination
	if ! [ -d "$destination" ] ; then
		lb_istrue $quiet_mode || echo "backup destination not reachable"
		return 4
	fi

	# if no backup lock exists, exit
	if ! current_lock -q ; then
		lb_istrue $quiet_mode || echo "backup is not running"
		return 0
	fi

	# get process PID
	local pid
	pid=$(current_lock -p)

	debug "File lock contains: $pid"

	if ! lb_is_integer "$pid" ; then
		lb_istrue $quiet_mode || echo "Cannot retrieve process PID! Please search it manually."
		return 7
	fi

	# search if time2backup is running
	if ps -f $pid &> /dev/null ; then
		lb_istrue $quiet_mode || echo "backup is running with PID $pid"
		return 5
	else
		# if no time2backup process found,
		lb_istrue $quiet_mode || echo "backup lock is here, but no backup is currently running"
		return 6
	fi
}


# Stop a running backup
# Usage: t2b_stop [OPTIONS]
t2b_stop() {
	# default options
	local force_mode=false

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-f|--force)
				force_mode=true
				;;
			-q|--quiet)
				quiet_mode=true
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# check status of backup
	t2b_status &> /dev/null

	# if no backup is running or error, cannot stop
	case $? in
		0)
			lb_istrue $quiet_mode || echo "backup is not running"
			return 0
			;;
		5)
			# backup is running: continue
			;;
		1)
			lb_istrue $quiet_mode || echo "Unknown error"
			return 6
			;;
		4)
			lb_istrue $quiet_mode || echo "backup destination not reachable"
			return 4
			;;
		*)
			lb_istrue $quiet_mode || echo "Cannot retrieve information about process"
			return 7
			;;
	esac

	local t2b_pid

	# get time2backup PID
	t2b_pid=$(current_lock -p)
	if ! lb_is_integer $t2b_pid ; then
		lb_istrue $quiet_mode || lb_error "PID not found"
		return 7
	fi

	debug "time2backup PID found: $t2b_pid"

	# prompt confirmation
	$force_mode || lb_yesno "Are you sure you want to interrupt the current backup (PID $t2b_pid)?" || return 0

	# send kill signal to time2backup
	if kill $t2b_pid ; then

		local rsync_pid

		# search for a current rsync command
		rsync_pid=$(ps -ef | grep -w $t2b_pid | grep "$rsync_path" | head -1 | awk '{print $2}')

		if lb_is_integer $rsync_pid ; then
			debug "Found rsync PID: $rsync_pid"

			# send the kill signal to rsync
			kill $rsync_pid || lb_warning "Failed to kill rsync PID $rsync_pid"
		fi

		# wait 30 sec max until time2backup is really stopped
		local i
		for i in $(seq 1 20) ; do
			if t2b_status &> /dev/null ; then
				break
			fi
			sleep 1
		done
	fi

	# recheck
	if t2b_status &> /dev/null ; then
		lb_istrue $quiet_mode || echo "time2backup was successfully stopped"
		return 0
	else
		lb_istrue $quiet_mode || echo "Still running! Could not stop time2backup process. You may retry in sudo."
		return 5
	fi
}


# Import backups
# Usage: t2b_import [OPTIONS] PATH [DATE...]
t2b_import() {
	if lb_istrue $clone_mode ; then
		lb_error "This command is disabled in clone mode."
		return 255
	fi

	if lb_istrue $remote_destination ; then
		echo "This command is disabled for remote destinations."
		return 255
	fi

	# default options
	local reference limit=0

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-l|--latest)
				limit=1
				;;
			--limit)
				limit=$(lb_getopt "$@")
				if ! lb_is_integer "$limit" || [ $limit -lt 1 ] ; then
					print_help
					return 1
				fi
				shift
				;;
			-r|--reference)
				reference=$(lb_getopt "$@")
				if ! check_backup_date "$reference" ; then
					print_help
					return 1
				fi
				shift
				;;
			-a|--all)
				sync_all=true
				;;
			-f|--force)
				force_mode=true
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# missing arguments
	if [ -z "$1" ] ; then
		print_help
		return 1
	fi

	# test backup destination
	prepare_destination || return 4

	local path=$1 backups=() existing_backups=()
	shift

	while [ $# -gt 0 ] ; do
		check_backup_date $1 && existing_backups+=($1)
		shift
	done

	# get available backups
	backups=($(get_backups))

	# prepare export destination
	case $(get_protocol "$path") in
		ssh)
			import_source=$(url2ssh "$path")
			remote_source=true

			# get backups to import
			[ ${#existing_backups[@]} = 0 ] && existing_backups=($(get_backups "$path"))
			;;

		*)
			# get destination path
			if [ "$lb_current_os" = Windows ] ; then
				# get UNIX format for Windows paths
				import_source=$(cygpath "$path")
			else
				import_source=$path
			fi

			# get backups to import
			[ ${#existing_backups[@]} = 0 ] && existing_backups=($(get_backups "$import_source"))
			;;
	esac

	# no backup found
	if [ ${#existing_backups[@]} = 0 ] ; then
		lb_error "No backups to import."
		return 0
	fi

	debug "Backups to import: ${existing_backups[*]}"

	local total=${#existing_backups[@]}
	if [ $limit -gt 0 ] ; then
		if [ $limit -lt $total ] ; then
			total=$limit
			limit=$((${#existing_backups[@]} - $limit))
		else
			limit=0
		fi
	fi

	lb_istrue $quiet_mode || lb_display "$total backups to import"

	# confirm action
	lb_istrue $force_mode || lb_yesno "Proceed to import?" || return 0

	# prepare rsync command
	prepare_rsync import

	local b d src cmd import result error errors=()
	for ((b=${#existing_backups[@]}-1; b>=$limit; b--)) ; do

		src=${existing_backups[b]}

		# prepare rsync command
		cmd=("${rsync_cmd[@]}" --delete)

		# if reference link not set, search the last existing backup
		if [ ${#backups[@]} -gt 0 ] ; then
			if [ -z "$reference" ] || [ "$reference" = "$src" ] ; then
				for ((d=${#backups[@]}-1; d>=0; d--)) ; do
					# avoid reference to be equal to the current item
					if [ "${backups[d]}" != "$src" ] ; then
						reference=${backups[d]}
						break
					fi
				done
			fi
		fi

		# add link and avoid to use the same backup date
		if [ -n "$reference" ] && [ "$reference" != "$src" ] ; then
			cmd+=(--link-dest ../"$reference")
		fi

		# add source and destination in rsync command
		cmd+=("$import_source/$src/" "$destination/$src")

		echo
		echo "Import $src... ($((${#existing_backups[@]} - $b))/$total)"

		# reset status
		import=true
		result=0

		if lb_istrue $sync_all ; then
			# sync all: only the latest
			end_loop=true
		else
			# search if backup has already been imported
			if lb_in_array $src "${backups[@]}" ; then
				echo "... Already imported"
				import=false
			fi
		fi

		while $import ; do
			debug_and_run "${cmd[@]}"
			lb_result
			result=$?

			debug "Result: $result"

			if [ $result != 0 ] ; then
				if rsync_result $result ; then
					error="Partial import $src (exit code: $result)"
				else
					error="Failed to import $src (exit code: $result)"
				fi

				lb_display_error "$error"

				# ask for retry; or else quit loop
				if ! lb_istrue $force_mode ; then
					lb_yesno -y -c "Retry?"
					case $? in
						0)
							# retry
							continue
							;;
						3)
							# cancel
							end_loop=true
							;;
					esac
				fi
			fi

			break
		done

		if [ $result = 0 ] ; then
			# change reference
			reference=$src
		else
			# append error message to report
			errors+=("$error")
		fi

		lb_istrue $end_loop && break
	done

	# full import
	if lb_istrue $sync_all ; then
		echo
		echo "Import all backups..."
		debug_and_run "${rsync_cmd[@]}" "$import_source/" "$destination"
		lb_result
		result=$?

		debug "Result: $result"

		if [ $result != 0 ] ; then
			if rsync_result $result ; then
				error="Partial import (exit code: $result)"
			else
				error="Failed to import (exit code: $result)"
			fi

			lb_display_error "$error"
			errors+=("$error")
		fi
	fi

	# print report
	echo
	if [ ${#errors[@]} = 0 ] ; then
		echo "Import finished"
	else
		echo "Some errors occurred while import:"
		local e
		for e in "${errors[@]}" ; do
			echo "   - $e"
		done

		return 6
	fi
}


# Export backups
# Usage: t2b_export [OPTIONS] PATH
t2b_export() {
	if lb_istrue $clone_mode ; then
		lb_error "This command is disabled in clone mode."
		return 255
	fi

	if lb_istrue $remote_destination ; then
		echo "This command is disabled for remote destinations."
		return 255
	fi

	# default options
	local reference limit=0

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-l|--latest)
				limit=1
				;;
			--limit)
				limit=$(lb_getopt "$@")
				if ! lb_is_integer "$limit" || [ $limit -lt 1 ] ; then
					print_help
					return 1
				fi
				shift
				;;
			-r|--reference)
				reference=$(lb_getopt "$@")
				if ! check_backup_date "$reference" ; then
					print_help
					return 1
				fi
				shift
				;;
			-a|--all)
				sync_all=true
				;;
			-f|--force)
				force_mode=true
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# missing arguments
	if [ -z "$1" ] ; then
		print_help
		return 1
	fi

	# test backup destination
	prepare_destination || return 4

	local -a backups existing_backups

	# get available backups
	backups=($(get_backups))

	# no backup found
	if [ ${#backups[@]} = 0 ] ; then
		lb_error "No backups to export."
		return 0
	fi

	# prepare export destination
	case $(get_protocol "$1") in
		ssh)
			export_destination=$(url2ssh "$*")
			remote_source=true

			# search for a backup reference
			[ -z "$reference" ] && existing_backups=($(get_backups "$*"))
			;;

		*)
			# get destination path
			if [ "$lb_current_os" = Windows ] ; then
				# get UNIX format for Windows paths
				export_destination=$(cygpath "$*")
			else
				export_destination=$*
			fi

			if [ -d "$export_destination" ] ; then
				# search for a backup reference
				[ -z "$reference" ] && existing_backups=($(get_backups "$export_destination"))
			else
				# create if not exists
				if ! mkdir -p "$export_destination" ; then
					lb_error "Cannot create folder $export_destination."
					lb_error "Please check your access rights."
					return 6
				fi
			fi
			;;
	esac

	debug "Existing backups: ${existing_backups[*]}"

	local total=${#backups[@]}
	if [ $limit -gt 0 ] ; then
		if [ $limit -lt $total ] ; then
			total=$limit
			limit=$((${#backups[@]} - $limit))
		else
			limit=0
		fi
	fi

	lb_istrue $quiet_mode || lb_display "$total backups to export"

	# confirm action
	lb_istrue $force_mode || lb_yesno "Proceed to export?" || return 0

	# prepare rsync command
	prepare_rsync export

	local b d src cmd export result error errors=()
	for ((b=${#backups[@]}-1; b>=$limit; b--)) ; do

		src=${backups[b]}

		# prepare rsync command
		cmd=("${rsync_cmd[@]}" --delete)

		# if reference link not set, search the last existing distant backup
		if [ ${#existing_backups[@]} -gt 0 ] ; then
			if [ -z "$reference" ] || [ "$reference" = "$src" ] ; then
				for ((d=${#existing_backups[@]}-1; d>=0; d--)) ; do
					# avoid reference to be equal to the current item
					if [ "${existing_backups[d]}" != "$src" ] ; then
						reference=${existing_backups[d]}
						break
					fi
				done
			fi
		fi

		# add link and avoid to use the same backup date
		if [ -n "$reference" ] && [ "$reference" != "$src" ] ; then
			cmd+=(--link-dest ../"$reference")
		fi

		# add source and destination in rsync command
		cmd+=("$destination/$src/" "$export_destination/$src")

		echo
		echo "Export $src... ($((${#backups[@]} - $b))/$total)"

		# reset status
		export=true
		result=0

		if lb_istrue $sync_all ; then
			# sync all: only the latest
			end_loop=true
		else
			# search if backup has already been exported
			if lb_in_array $src "${existing_backups[@]}" ; then
				echo "... Already exported"
				export=false
			fi
		fi

		while $export ; do
			debug_and_run "${cmd[@]}"
			lb_result
			result=$?

			debug "Result: $result"

			if [ $result != 0 ] ; then
				if rsync_result $result ; then
					error="Partial export $src (exit code: $result)"
				else
					error="Failed to export $src (exit code: $result)"
				fi

				lb_display_error "$error"

				# ask for retry; or else quit loop
				if ! lb_istrue $force_mode ; then
					lb_yesno -y -c "Retry?"
					case $? in
						0)
							# retry
							continue
							;;
						3)
							# cancel
							end_loop=true
							;;
					esac
				fi
			fi

			break
		done

		if [ $result = 0 ] ; then
			# change reference
			reference=$src
		else
			# append error message to report
			errors+=("$error")
		fi

		lb_istrue $end_loop && break
	done

	# full export
	if lb_istrue $sync_all ; then
		echo
		echo "Export all backups..."
		debug_and_run "${rsync_cmd[@]}" "$destination/" "$export_destination"
		lb_result
		result=$?

		debug "Result: $result"

		if [ $result != 0 ] ; then
			if rsync_result $result ; then
				error="Partial export (exit code: $result)"
			else
				error="Failed to export (exit code: $result)"
			fi

			lb_display_error "$error"
			errors+=("$error")
		fi
	fi

	# print report
	echo
	if [ ${#errors[@]} = 0 ] ; then
		echo "Export finished"
	else
		echo "Some errors occurred while export:"
		local e
		for e in "${errors[@]}" ; do
			echo "   - $e"
		done

		return 6
	fi
}


# Install time2backup
# Usage: t2b_install [OPTIONS]
t2b_install() {
	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# create a desktop file (Linux)
	if [ "$lb_current_os" = Linux ] ; then

		desktop_file=$lb_current_script_directory/time2backup.desktop

		echo "[Desktop Entry]
Version=1.0
Name=time2backup
GenericName=Files backup
Comment=Backup and restore your files
GenericName[fr]=Sauvegarde de fichiers
Comment[fr]=Sauvegardez et restaurez vos données
Type=Application
Exec=$(lb_realpath "$lb_current_script") $*
Icon=$(lb_realpath "$lb_current_script_directory"/resources/icon.png)
Terminal=true
Categories=System;Utility;Filesystem;
" > "$desktop_file"

		# copy desktop file to /usr/share/applications
		if [ -d /usr/share/applications ] ; then
			cp -f "$desktop_file" /usr/share/applications/ &> /dev/null
			if [ $? != 0 ] ; then
				echo
				echo "Cannot create application link. It's not critical, but you may not have the icon on your system."
				echo "You may have to run install command in sudo."
				lb_exitcode=4
			fi
		fi
	fi

	local create_link=true

	# if alias already exists,
	if [ -e "$cmd_alias" ] ; then
		# if the same path, do not recreate link
		if [ "$(lb_realpath "$cmd_alias")" = "$(lb_realpath "$lb_current_script")" ] ; then
			create_link=false
		fi
	fi

	# (re)create link
	if $create_link ; then
		ln -snf "$lb_current_script" "$cmd_alias" &> /dev/null
		if [ $? != 0 ] ; then
			echo
			echo "Cannot create command link. It's not critical, but you may not run time2backup command directly."
			echo "You may have to run install command in sudo, or add an alias in your bashrc file."

			# this exit code is less important
			[ $lb_exitcode = 0 ] && lb_exitcode=4
		fi
	fi

	# copy bash completion script
	cp "$lb_current_script_directory"/resources/t2b_completion /etc/bash_completion.d/time2backup
	if [ $? != 0 ] ; then
		echo
		echo "Cannot install bash completion script. It's not critical, but you can retry in sudo."

		# this exit code is less important
		[ $lb_exitcode = 0 ] && lb_exitcode=5
	fi

	# make completion working in the current session (does not need to create a new one)
	. "$lb_current_script_directory"/resources/t2b_completion

	echo "time2backup is installed"

	return $lb_exitcode
}


# Uninstall time2backup
# Usage: t2b_uninstall [OPTIONS]
t2b_uninstall() {
	# default options
	local delete_files=false force_mode=false

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-y|--yes)
				force_mode=true
				;;
			-x|--delete-files)
				delete_files=true
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# confirm action
	$force_mode || lb_yesno "Uninstall time2backup?" || return 0

	echo "Uninstall time2backup..."

	# delete cron job
	if ! crontab_config disable &> /dev/null ; then
		lb_error "Failed to remove cron job(s). Please remove them manually."
		lb_exitcode=3
	fi

	# delete desktop file (Linux)
	application_link=/usr/share/applications/time2backup.desktop

	# delete desktop file
	if [ -f "$application_link" ] ; then
		if ! rm -f "$application_link" ; then
			lb_error "Failed to remove application link.  You may have to run in sudo."
			lb_exitcode=4
		fi
	fi

	# delete alias if exists
	if [ -e "$cmd_alias" ] ; then
		if ! rm -f "$cmd_alias" ; then
			lb_error "Failed to remove command alias. You may have to run in sudo."
			lb_exitcode=5
		fi
	fi

	# delete files
	if $delete_files ; then
		if ! rm -rf "$lb_current_script_directory" ; then
			lb_error "Failed to delete time2backup directory. You may have to run in sudo."
			lb_exitcode=6
		fi
	fi

	# delete bash completion script
	if [ -f /etc/bash_completion.d/time2backup ] ; then
		if ! rm -f /etc/bash_completion.d/time2backup ; then
			lb_error "Failed to remove bash auto-completion script. You may have to run in sudo."
			lb_exitcode=7
		fi

		# reset completion for current session
		complete -W "" time2backup &> /dev/null
	fi

	# simple print
	if [ $lb_exitcode = 0 ] ; then
		echo
		echo "time2backup is uninstalled"
	fi

	# we quit as soon as possible (do not use libbash that may be already deleted)
	# do not exit with error to avoid crashes in packages removal
	exit
}
