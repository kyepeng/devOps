FOLDER=$1;

if [ -z "${FOLDER}" ]
then
    FOLDER=`pwd`;
fi

find "${FOLDER}" -name '*.md' -print0 | while read -d $'\0' file
do
    WITHOUT_EXTENSION=`echo $file | cut -d '.' -f 1`;
    pandoc "$file" -o "$WITHOUT_EXTENSION.docx"
done

find "${FOLDER}" -name '*.md' -print0 | while read -d $'\0' file
do
    rm -f "$file"
done