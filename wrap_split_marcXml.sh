#!/bin/sh

#Wrap MarcXML records created from xml_split so they are valid MARCXML.

# Check if a folder path argument was provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path_to_xml_folder>"
    exit 1
fi

#WARNING: edits files in place!
for file in $1/*.xml; do
    perl -l -pi -e 'print "<collection xmlns=\"http://www.loc.gov/MARC21/slim\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:schemaLocation=\"http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd\">" if $. == 2' $file
    echo '</collection>' >> $file
done