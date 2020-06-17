#!/bin/bash

# Shell script for merging a set of protobuf files
# Usage: $0 [*.proto path with the api definition]
# $0 basedir/././file.proto
# EXIT CODES
# 0 - Success
# 97 - Nothing to merge
# 98 - Import file don't exist
# 99 - File don't exist or isn't a proto

FULL_NAME=$0
PRM_PROTOPATH=$1 

EXIT_CODE=0
VERBOSE=false
DEEP_LEVEL=4

PID="$$" #Process PID in order to indentify each execution
BASE_DIR=$(dirname $FULL_NAME)
BASE_NAME=$(basename $FULL_NAME | sed "s/.sh//")
MAIN_PROTO="${BASE_DIR}/${PRM_PROTOPATH}"

if [ ! -f $MAIN_PROTO ] || [[ $MAIN_PROTO != *.proto ]]; then
    echo "File don't exist or isn't a proto in base dir $MAIN_PROTO"
    exit 99
fi

##<<<<<< Functions Section Start >>>>>>>
# Function for loggin in a log fine setted in the same path
logger () {
  local LOG_LEVEL=$1
  shift
  local MSG=$@
  local TIMESTAMP=$(/bin/date +"%Y-%m-%d %T")
  if [ $LOG_LEVEL = 'ERROR' ] || $VERBOSE ; then
    echo "${TIMESTAMP} ${FULL_NAME} ${LOG_LEVEL} ${PID}: ${MSG}"  >> $LOG_FILE
  fi
}

importProto() {
    local PROTO_LIST=("$@")
    local RESULT=()
    local INDX=0

    for PROTO in "${PROTO_LIST[@]}"; do
        local PROTO_PATH=${PROTO#*|};
        logger INFO "Importing $PROTO_PATH"
        OIFS=$IFS
        IFS=
        while read LINE || [ -n "$LINE" ]; do
            if [[ $LINE =~ ^\s*import.*$BASE_PACKAGE.*$ ]]; then
                local PATH=${LINE#*\"};
                PATH=${PATH%\"*};
                local ABSOLUTE_PATH="${BASE_DIR}/${PATH}" 
                if [ -f $ABSOLUTE_PATH ]; then
                    local DIR="${PATH%/*}/"
                    RESULT[$INDX]="${DIR//\//.}|$PATH"
                    let INDX+=1
                else
                    logger ERROR "Proto file don't exist in the base package $BASE_PACKAGE: $ABSOLUTE_PATH"
                    EXIT_CODE=98
                fi
            else
                if [[ $LINE =~ ^\s*import.*$ ]]; then
                    echo $LINE >> $IMPORT_SECTION      
                else
                    if ! [[ "$LINE" =~ ^(syntax|package|option) ]]; then
                        for PACKAGE in "${RESULT[@]}"; do
                            PACKAGE=${PACKAGE%|*};
                            LINE=("${LINE/$PACKAGE/}")
                        done
                        LINE=("${LINE// \[\(validate.*/;}")
                        echo $LINE  >> $PRINTER
                    fi
                fi
            fi
        done < $PROTO_PATH
        IFS=$OIFS
        logger INFO "Imported $PROTO_PATH"
    done
    echo "${RESULT[@]}"
    return $EXIT_CODE
}
##<<<<<< Functions Section End >>>>>>>

BASE_PACKAGE=${PRM_PROTOPATH%%/*}
BASE_PROTO_NAME=$(basename $MAIN_PROTO | sed "s/.proto//")
COMBINED_PROTO="${BASE_PROTO_NAME}_merged.proto"
IMPORT_SECTION="${BASE_PROTO_NAME}_import.tmp"
HEADER_SECTION="${BASE_PROTO_NAME}_header.tmp"
BODY_SECTION="${BASE_PROTO_NAME}_body.tmp"
LOG_FILE="${BASE_DIR}/${BASE_NAME}.log"

rm -f $COMBINED_PROTO
rm -f *.tmp

IMPORT_PROTO_LIST=()
IMPORT_INDX=0
PRINTER=$HEADER_SECTION

logger INFO "Starting merge of $MAIN_PROTO"

#Loop main proto file
OIFS=$IFS
IFS=
while read LINE || [ -n "$LINE" ]; do

    #If the line is an import in the base dir
    if [[ $LINE =~ ^\s*import.*$BASE_PACKAGE.*$ ]]; then
        IMPORT_PATH=$(echo "$LINE" | cut -d'"' -f 2)
        IMPORT_ABSOLUTE_PATH="${BASE_DIR}/${IMPORT_PATH}"
        if [ -f $IMPORT_ABSOLUTE_PATH ]; then
            #If the proto file exist include it in the next import iteration
            NOFILE_PATH="${IMPORT_PATH%/*}/"
            IMPORT_PROTO_LIST[$IMPORT_INDX]="${NOFILE_PATH//\//.}|$IMPORT_ABSOLUTE_PATH"
            let IMPORT_INDX+=1
            if [ ! -f $BODY_SECTION ]; then
                PRINTER=$BODY_SECTION
            fi
        else
            logger ERROR "Proto file don't exist in the base package $BASE_PACKAGE: $ABSOLUTE_PATH"
            EXIT_CODE=98
        fi
    else
        #If is an external import
        if [[ $LINE =~ ^\s*import.*$ ]]; then
            echo $LINE >> $IMPORT_SECTION
        else
            #If isnt an import line check if has any import package refrence
            for PACKAGE in "${IMPORT_PROTO_LIST[@]}"; do
                PACKAGE=${PACKAGE%|*};
                LINE=("${LINE/$PACKAGE/}")
            done
            #Remove validations
            LINE=("${LINE/^\s\[\(validate\.\w+\)\S+\s\=\s\S+\]/}")
            echo $LINE  >> $PRINTER
        fi
    fi
done < $MAIN_PROTO
IFS=$OIFS

if [ -n "$IMPORT_PROTO_LIST" ]; then
    CURRENT_LEVEL="${IMPORT_PROTO_LIST[@]}"
    for ((i=1;i<=$DEEP_LEVEL;i++)); 
    do
        logger INFO "LEVEL $i Start: {${CURRENT_LEVEL[@]}}"
        NEXT_LEVEL=($(importProto ${CURRENT_LEVEL[@]}))
        EXIT_CODE=$?
        logger INFO "LEVEL $i End: exit_code=$EXIT_CODE result={${NEXT_LEVEL[@]}}"
        if [ ! -n "$NEXT_LEVEL" ]; then
            logger INFO "There aren't coming imports to process"
            break
        fi
        CURRENT_LEVEL="${NEXT_LEVEL[@]}"
    done
    #Remove validation proto import from section file
    IMPORT_SECTION_FILTER="${BASE_PROTO_NAME}_import_filter.tmp"
    echo $(sed '/.*validate.*proto.*/d' $IMPORT_SECTION) >> $IMPORT_SECTION_FILTER

    #Get uniq imports
    IMPORT_SECTION_UNIQ="${BASE_PROTO_NAME}_import_uniq.tmp"
    echo $(sort $IMPORT_SECTION_FILTER | uniq) >> $IMPORT_SECTION_UNIQ

    #Merging proto sections
    cat $HEADER_SECTION $IMPORT_SECTION_UNIQ $BODY_SECTION > $COMBINED_PROTO
else
    echo "Nothing to merge"
    EXIT_CODE=97
fi
rm *.tmp
logger INFO "End merge with exit code $EXIT_CODE of $MAIN_PROTO"
if [[ $EXIT_CODE -ne 0 ]]; then
  echo "Proto files merged with errors, you can find more infomation in $LOG_FILE";
fi
exit $EXIT_CODE
