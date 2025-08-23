#!/bin/bash
#
#  time2backup portable
#  It's time to backup your files!
#
#  Sources: https://github.com/time2backup/time2backup
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

# run time2backup with local config
"$script_directory"/time2backup.sh -c "$script_directory"/config "$@"
