#!/bin/sh

#Check if any arguments were not specified
if [ $# -ne 2 ]; then
    echo "Error: Please provide exactly two arguments -writefile and writestr"
    exit 1
fi

#Check if the two arguments is empty
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error: Both arguments cannot be empty"
    exit 1
fi


writefile="$1"
writestr="$2"

#Check if write file is a valid path ( and create directories if needed )
if  ! mkdir -p "$(dirname "$writefile")" ; then
    echo "Error: the path is not valid"
    exit 1
fi

#Write the content to the file
if ! echo "$writestr" > "$writefile" ; then
    echo "Error: Failed to write to the file"
    exit 1
fi

echo "Content was written to the $writefile successfully"
