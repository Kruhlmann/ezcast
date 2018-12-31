#!/bin/bash
#
# Reads a JSON file and downloads youtube videos based on the URLs it contains.
#
# Arguments:
#	$1: Directory to deploy audio to

# Verify that paths are in the correct format (ends with forwardslash).
IMPORT_DIR="~/tmp/"
EXPORT_DIR="${1%/}/"

##################################################################
# Takes the name of an executable and returns an integer.
# Globals:
#	None
# Arguments:
#	$1: Executable to locate
# Returns
#	0 if executable was found 0 otherwise 1
##################################################################
EXECUTABLE_IN_PATH() {
	[[ -x "$(command -v $1)" ]]
}

##################################################################
# Attempts to find the correct package management tool for the os,
# and then installs a parsed package on the machine.
# Globals:
#	None
# Arguments:
#	$1: Name of the package
# Returns
#	Name of the package manager found
##################################################################
INSTALL_PACKAGE() {
	# Attempt to find package manager.
	PKMGR="apt-get install"
	if EXECUTABLE_IN_PATH "dnf"; then PKMGR="dnf install ";
	elif EXECUTABLE_IN_PATH "yum"; then PKMGR="yum install ";
	elif EXECUTABLE_IN_PATH "pacman"; then PKMGR="pacman -S ";
	elif EXECUTABLE_IN_PATH "zypper"; then PKMGR="zypper install ";
	elif EXECUTABLE_IN_PATH "apt"; then PKMGR="apt install "; fi
	# Install package.
	$PKMGR $1 > /dev/null 2>&1
	return 0
}

printf "Verifying requirements\n"
# Check if youtube-dl is installed.
if ! EXECUTABLE_IN_PATH "youtube-dl"; then
	printf "\t\e[1;31m✕\e[0m youtube-dl\r"
	if [[ "$EUID" -ne 0 ]]; then
		# Requirements can only be installed as root.
		printf "\nYou are missing requirements. Re-run with sudo to have them installed.\n"
		exit 1
	else
		# Download the youtube-dl requirement.
		printf "\t\e[1;33m⬇\e[0m youtube-dl\r"
		if ! EXECUTABLE_IN_PATH "curl"; then
			# Use wget if curl is not installed.
			wget "https://yt-dl.org/downloads/latest/youtube-dl" -O "/usr/local/bin/youtube-dl" >/dev/null 2>&1
		else
			curl -L "https://yt-dl.org/downloads/latest/youtube-dl" -o "/usr/local/bin/youtube-dl" >/dev/null 2>&1
		fi
		# Add permissions.
		chmod a+rx "/usr/local/bin/youtube-dl" > /dev/null 2>&1
	fi
fi
# Requirement satisfied.
printf "\t\e[1;32m✓\e[0m youtube-dl\n"

# Check if ffmpeg is installed.
if ! EXECUTABLE_IN_PATH "ffmpeg"; then
	printf "\t\e[1;31m✕\e[0m ffmpeg\r"
	if [ "$EUID" -ne 0 ]; then
		# Requirements can only be installed as root.
		printf "\nYou are missing requirements. Re-run with sudo to have them installed."
		exit 1
	else
		# Download the youtube-dl requirement.
		printf "\t\e[1;33m⬇\e[0m ffmpeg\r"
		INSTALL_PACKAGE "ffmpeg"
	fi
fi
# Requirement satisfied.
printf "\t\e[1;32m✓\e[0m ffmpeg\n"

# Stop the program if the user is running as root.
# This is to stop the user from accidentally placing files in the
# /home/root/ directory.
if [ "$EUID" -eq 0 ]; then
	printf "All requirements are met. Please run the script without elevated priviledges.\n"
	exit 0
fi

# Prioritize user config file over global.
CONFIG_FILE="/etc/ezcast/config"
if [[ -f "~/.config/ezcast/config" ]]; then
	CONFIG_FILE="~/.config/ezcast/config"
elif ! [[ -f $CONFIG_FILE ]]; then
	printf "Unable to locate any configuration files.\n"
	exit 1
fi

# Download audio files.
SUBSCRIPTIONS=()
while read -r LINE; do
	# If the line is not a comment add it to the URL array and count it.
	if ! [[ $LINE = \#* ]]; then
		FILE_COUNT=$((FILE_COUNT + 1))
		SUBSCRIPTIONS+=($LINE)
	fi
done < "$CONFIG_FILE"

printf "Download in progress, \e[1;33mthis may take a while\e[0m\n"
for URL in ${SUBSCRIPTIONS[*]}; do
	printf "\t\e[1;33m⬇\e[0m Downloading $URL\r"
	# Arguments:
	# 	-w: Don't overwrite files.
	# 	--restrict-filenames: Use only ASCII characters for filenames.
	# 	--geo-bypass: Attempt to bypass georestrictions.
	# 	-f bestaudio: Download best audio format avaliable.
	# 	-o $IMPORT_DIR%(uploader)s-%(title)s.%(ext)s: Export file and format.
	# 	--no-cache-dir: Don't read cached results.
	# 	: URL of the target.
	youtube-dl -w --restrict-filenames --geo-bypass -f bestaudio -o "$IMPORT_DIR%(uploader)s-%(title)s.%(ext)s" --no-cache-dir $URL > ~/.logs/ezcast
	printf "\t\e[1;32m✓\e[0m Downloading $URL\n"
done
printf "Download complete\n"

# Convert all the files from WEBM to MP3 using ffmpeg.
FILE_COUNT=$(find $IMPORT_DIR -name "*.webm" | wc -l)
COUNT=1

# Subtract files, which are already converted from the total.
for FILE in $IMPORT_DIR*.webm; do
	NEW_FILE="$EXPORT_PATH${FILE%.webm}.mp3"
	if [[ -f $NEW_FILE ]]; then
		FILE_COUNT=$((FILE_COUNT + 1))
	fi
done;

printf "Found \e[1;36m$FILE_COUNT\e[0m unconverted webm files in \e[1;32m$IMPORT_DIR\e[0m\n"

# Avoid division by 0 error.
if [[ $FILE_COUNT -eq 0 ]]; then
	printf "No new files detected. Exiting.\n"
	exit 0
fi;

for FILE in $IMPORT_DIR*.webm $IMPORT_DIR*.m4a; do
	COL_COUNT=$(tput cols)
	PERCENTAGE=$(((COUNT * 100) / FILE_COUNT))
	COL_DONE=$(((PERCENTAGE * COL_COUNT) / 100))
	PREFIX="Converting ($COUNT/$FILE_COUNT)"
	NEW_FILE="$EXPORT_PATH${FILE%.webm}.mp3"
	# Only convert file if it's missing in the export directory.
	if ! [[ -f $NEW_FILE ]]; then
		printf "$PREFIX "
		# print the first "filled out" part of the progress bar.
		printf "▓%.0s" $(seq 1 $((COL_DONE)))
		# Print the rest of the bar using spaces.
		printf "░%.0s" $(seq 1 $((COL_COUNT - COL_DONE - ${#PREFIX} - 4)))
		printf "\r"
		ffmpeg -i "${FILE}" -vn -ab 128k -ar 44100 -y "${NEW_FILE}" > /dev/null 2>&1;
		COUNT=$((COUNT + 1))
	fi
done;
