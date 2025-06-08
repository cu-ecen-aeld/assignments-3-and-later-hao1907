#!/bin/sh

#Check if any arguments were not specified
if [ $# -ne 2 ]; then
    echo "Error: Please provide exactly two arguments -filesdir and searchstr"
    exit 1
fi

#Check if the first argument is a directory
if [ ! -d "$1" ]; then
    echo "Error: $1 is not a directory"
    exit 1
fi

#Check if the second argument is a string
if [ -z "$2" ]; then
    echo "Error: Second argument cannot be empty"
    exit 1
fi

filesdir="$1"
searchstr="$2"

#Count the nmber of files and matching lines
file_count=$(find "$filesdir" -type f | wc -l)
matching_lines=$(grep -r "$searchstr" "$filesdir" | wc -l)

#Print the results
echo "The number of files are $file_count and the number of matching lines are $matching_lines"
