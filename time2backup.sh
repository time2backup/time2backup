#!/bin/bash
#
#  time2backup
#  It's time to backup your files!
#
#  Website: https://time2backup.org
#  MIT License
#  Copyright (c) 2017-2020 Jean Prunneaux
#
#  Version 1.8.2 (2020-07-06)
#

declare -r version=1.8.2


#
#  Initialization
#

# get real path of the script
if [ "$(uname)" = Darwin ] ; then
	# macOS which does not support readlink -f option
	current_script=$(perl -e 'use Cwd "abs_path";print abs_path(shift)' "$0")
else
	current_script=$(readlink -f "$0")
fi

# get directory of the current script
script_directory=$(dirname "$current_script")

# load libbash
source "$script_directory"/libbash/libbash.sh --gui &> /dev/null
if [ $? != 0 ] ; then
	echo >&2 "[ERROR] cannot load libbash.sh"
	exit 1
fi

# load default english messages
source "$script_directory"/locales/en.sh
if [ $? != 0 ] ; then
	lb_error "[ERROR] cannot load english messages"
	exit 1
fi

# load translation (don't care of errors)
source "$script_directory/locales/${LANG:0:2}.sh" &> /dev/null

# change current script name
lb_current_script_name=time2backup


#
#  Main program
#

# load init config
source "$script_directory"/inc/init.sh
if [ $? != 0 ] ; then
	lb_error "[ERROR] cannot load init script"
	exit 1
fi

# load functions
source "$script_directory"/inc/functions.sh
if [ $? != 0 ] ; then
	lb_error "[ERROR] cannot load functions"
	exit 1
fi

# load commands
source "$script_directory"/inc/commands.sh
if [ $? != 0 ] ; then
	lb_error "[ERROR] cannot load commands"
	exit 1
fi

# load help
source "$script_directory"/inc/help.sh
if [ $? != 0 ] ; then
	lb_error "[ERROR] cannot load help"
	exit 1
fi

# load the default config
if ! lb_import_config "$script_directory"/config/default.example.conf ; then
	lb_error "[ERROR] cannot load core config"
	exit 1
fi

# load the default config if exists
if [ -f "$script_directory"/config/default.conf ] ; then
	if ! lb_import_config "$script_directory"/config/default.conf ; then
		lb_error "[ERROR] cannot load default config"
		exit 3
	fi
fi

# get arguments
lb_getargs "$@" && set -- "${lb_getargs[@]}"

# get global options
while [ $# -gt 0 ] ; do
	case $1 in
		-c|--config)
			# custom config path
			config_directory=$(lb_getopt "$@")
			if [ -z "$config_directory" ] ; then
				print_help global
				exit 1
			fi
			shift
			;;
		-d|--destination)
			force_destination=$(lb_getopt "$@")
			if [ -z "$force_destination" ] ; then
				print_help global
				exit 1
			fi
			destination=$force_destination
			shift
			;;
		-u|--user)
			# run as a custom user
			user=$(lb_getopt "$@")
			if [ -z "$user" ] ; then
				print_help global
				exit 1
			fi
			shift
			;;
		-l|--log-level)
			force_log_level=$(lb_getopt "$@")
			if [ -z "$force_log_level" ] ; then
				print_help global
				exit 1
			fi
			shift
			;;
		-v|--verbose-level)
			force_verbose_level=$(lb_getopt "$@")
			if [ -z "$force_verbose_level" ] ; then
				print_help global
				exit 1
			fi
			shift
			;;
		-C|--console)
			console_mode=true
			;;
		-D|--debug)
			debug_mode=true
			;;
		-V|--version)
			echo $version
			exit
			;;
		-h|--help)
			print_help global
			exit
			;;
		-*)
			print_help global
			exit 1
			;;
		*)
			break
			;;
	esac
	shift # load next argument
done

# get main command
command=$1
shift

# if user not set, get current user
[ -z "$user" ] && user=$lb_current_user

# set console mode
if lb_istrue $console_mode ; then
	lbg_set_gui console
	# disable notifications
	notifications=false
else
	# try to find display (if into a cron job on Linux)
	if [ "$lb_current_os" = Linux ] ; then

		u=$user

		for i in 1 2 ; do
			# find user X display
			xdisplay=$(who | grep "^$u .*(:[0-9])$" | head -1 | sed "s/.*(\(:[0-9]*\))$/\1/g")

			# if found,
			if [ -n "$xdisplay" ] ; then
				# export the X display variable
				export DISPLAY=$xdisplay

				# reset GUI tools
				lbg_set_gui
				break
			fi

			# if failed, try with the current user
			u=$lb_current_user
		done
	fi
fi

# set verbose and log levels
set_verbose_log_levels

# validate commands
case $command in
	""|backup|restore|history|explore|config|mv|clean|rotate|import|export)
		# search for quiet mode option
		for ((i=1; i<=$#; i++)) ; do
			case ${!i} in
				-q|--quiet)
					quiet_mode=true
					break
					;;
			esac
		done
		;;

	status|stop)
		# if destination specified, do not load config
		if [ -n "$destination" ] ; then
			# run command then exit
			t2b_$command "$@"
			exit $?
		fi
		;;

	install|uninstall)
		# not depending on configuration: run command then exit
		t2b_$command "$@"
		exit $?
		;;

	*)
		# invalid commands
		print_help global
		exit 1
		;;
esac

if [ -n "$config_directory" ] ; then
	# get current config directory absolute path
	config_directory=$(lb_abspath "$config_directory")
	if [ $? != 0 ] ; then
		# try to get parent directory path
		parent_config_directory=$(lb_abspath "$(dirname "$config_directory")")
		if [ $? != 0 ] ; then
			lb_error "Please set an existing directory for config path!"
			exit 3
		fi
		config_directory=$parent_config_directory/$(basename "$config_directory")
	fi
else
	# default config directory
	if [ -n "$default_config_directory" ] ; then
		config_directory=$default_config_directory
	else
		config_directory=$(lb_homepath $user)/.config/time2backup/
		if [ $? != 0 ] ; then
			lbg_error "$tr_error_getting_homepath_1\n$tr_error_getting_homepath_2"
			exit 3
		fi
	fi
fi

# define config files
config_file=$config_directory/time2backup.conf
config_sources=$config_directory/sources.conf
config_excludes=$config_directory/excludes.conf
config_includes=$config_directory/includes.conf

if ! lb_istrue $quiet_mode ; then
	case $command in
		status|stop)
			# don't print version
			;;
		*)
			echo "time2backup $version"
			;;
	esac

	debug "Using config file: $config_file"
fi

# if config file exists and is not empty
if [ -f "$config_file" ] && [ -s "$config_file" ] ; then
	# upgrade config if needed
	if ! upgrade_config ; then
		# if failed, display an error and quit
		if lb_istrue $quiet_mode ; then
			lb_error "$tr_error_upgrade_config"
		else
			lbg_error "$tr_error_upgrade_config"
		fi
		exit 3
	fi

	# load config; ignore errors
	load_config &> /dev/null
fi

# security recheck: set default rsync path if not defined
[ -z "$rsync_path" ] && rsync_path=$default_rsync_path

# test if rsync command is available
if ! lb_command_exists "$rsync_path" ; then
	lbg_critical "$tr_error_no_rsync_1\n$tr_error_no_rsync_2"
	exit 1
fi

# create config files if needed
if ! create_config ; then
	lbg_error "$tr_error_create_config"
	exit 3
fi

# if configuration is not set (destination empty), run first config wizard
if [ -z "$destination" ] ; then
	config_wizard
	exit $?
fi

# display choose operation dialog if not set
while [ -z "$command" ] ; do
	choose_operation

	# do not close time2backup when config is finished
	case $command in
		config)
			t2b_config
			command=""
			;;
		""|exit)
			exit 0
			;;
	esac
done

case $command in
	config)
		# commands that do not need to load config: do nothing
		;;
	*)
		# test configuration
		if ! load_config ; then
			lb_error "There are errors in your configuration."
			lb_error "Please edit your configuration with 'config' command or manually."
			exit 3
		fi

		# (re)set verbose and log levels after config was loaded
		set_verbose_log_levels

		# apply configuration in a quiet mode; don't care of errors
		apply_config &> /dev/null
		;;
esac

# run command
t2b_$command "$@"
lb_exitcode=$?

debug "Exited with code: $lb_exitcode"

lb_exit
