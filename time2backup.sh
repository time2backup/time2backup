#!/bin/bash
#
#  time2backup
#  It's time to backup your files!
#
#  Website: https://time2backup.org
#  MIT License
#  Copyright (c) 2017-2018 Jean Prunneaux
#
#  Version 1.4.0 (2018-08-19)
#

version=1.4.0-rc.1


#
#  Initialization
#

# get real path of the script
if [ "$(uname)" == Darwin ] ; then
	# macOS which does not support readlink -f option
	current_script=$(perl -e 'use Cwd "abs_path";print abs_path(shift)' "$0")
else
	current_script=$(readlink -f "$0")
fi

# get directory of the current script
script_directory=$(dirname "$current_script")

# load libbash
source "$script_directory/libbash/libbash.sh" --gui &> /dev/null
if [ $? != 0 ] ; then
	echo >&2 "time2backup: [ERROR] cannot load libbash.sh"
	exit 1
fi

# load default english messages
source "$script_directory/locales/en.sh" > /dev/null
if [ $? != 0 ] ; then
	lb_error "time2backup: [ERROR] cannot load messages!"
	exit 1
fi

# load translation (don't care of errors)
source "$script_directory/locales/$lb_lang.sh" &> /dev/null

# change current script name
lb_current_script_name=time2backup


#
#  Functions
#

# load init config
source "$script_directory/inc/init.sh" > /dev/null
if [ $? != 0 ] ; then
	lb_error "time2backup: [ERROR] cannot load init!"
	exit 1
fi

# load functions
source "$script_directory/inc/functions.sh" > /dev/null
if [ $? != 0 ] ; then
	lb_error "time2backup: [ERROR] cannot load functions!"
	exit 1
fi

# load commands
source "$script_directory/inc/commands.sh" > /dev/null
if [ $? != 0 ] ; then
	lb_error "time2backup: [ERROR] cannot load commands!"
	exit 1
fi

# load help
source "$script_directory/inc/help.sh" > /dev/null
if [ $? != 0 ] ; then
	lb_error "time2backup: [ERROR] cannot load help!"
	exit 1
fi


#
#  Main program
#

# load the default config if exists
if [ -f "$script_directory/config/default.conf" ] ; then
	# load the default config
	if ! lb_import_config "$script_directory/config/default.conf" ; then
		echo "time2backup: [ERROR] cannot load default config!"
		exit 3
	fi
fi

# get global options
while [ $# -gt 0 ] ; do
	case $1 in
		-C|--console)
			console_mode=true
			;;
		-u|--user)
			# run as user
			if [ -z "$2" ] ; then
				print_help global
				exit 1
			fi
			user=$2
			shift
			;;
		-l|--log-level)
			if [ -z "$2" ] ; then
				print_help global
				exit 1
			fi
			log_level=$2
			shift
			;;
		-v|--verbose-level)
			if [ -z "$2" ] ; then
				print_help global
				exit 1
			fi
			verbose_level=$2
			shift
			;;
		-d|--destination)
			if [ -z "$2" ] ; then
				print_help global
				exit 1
			fi
			force_destination=$2
			shift
			;;
		-c|--config)
			# custom config path
			if [ -z "$2" ] ; then
				print_help global
				exit 1
			fi
			config_directory=$2
			shift
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
if $console_mode ; then
	lbg_set_gui console
	# disable notifications by default
	notifications=false
else
	# try to find display (if into a cron job on Linux)
	if [ "$lb_current_os" == Linux ] ; then

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

if $debug_mode ; then
	lb_debug "Running in DEBUG mode..."
else
	# defines log level
	# if not set (unknown error), set to default level
	if ! lb_set_log_level "$log_level" ; then
		lb_set_log_level "$default_log_level"
	fi

	# defines verbose level
	# if not set (unknown error), set to default level
	if ! lb_set_display_level "$verbose_level" ; then
		lb_set_display_level "$default_verbose_level"
	fi
fi

# validate commands
case $command in
	""|backup|restore|history|explore|status|stop|mv|clean|config)
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

	install|uninstall)
		# run commands not depending on configuration
		t2b_cmd=(t2b_$command)

		# forward arguments in space safe mode
		while [ $# -gt 0 ] ; do
			t2b_cmd+=("$1")
			shift
		done

		# run command and exit
		"${t2b_cmd[@]}"
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

if ! $quiet_mode ; then
	case $command in
		""|backup|restore)
			echo "time2backup $version"
			;;
	esac

	lb_debug "Using config file: $config_file"
fi

# if config file exists
if [ -f "$config_file" ] ; then

	# upgrade config if needed
	if ! upgrade_config ; then

		# if failed, display an error and quit
		if $quiet_mode ; then
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
if [ -z "$rsync_path" ] ; then
	rsync_path=$default_rsync_path
fi

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
[ -z "$command" ] && choose_operation

# commands that needs to load config
if [ $command != config ] ; then
	# test configuration
	if ! load_config ; then
		lb_error "There are errors in your configuration."
		lb_error "Please edit your configuration with 'config' command or manually."
		exit 3
	fi

	# apply configuration in a quiet mode; don't care of errors
	apply_config &> /dev/null
fi

# prepare command
t2b_cmd=(t2b_$command)

# forward arguments in space safe mode
while [ $# -gt 0 ] ; do
	t2b_cmd+=("$1")
	shift
done

# run command
"${t2b_cmd[@]}"

lb_exitcode=$?

lb_debug "Exited with code: $lb_exitcode"

lb_exit
