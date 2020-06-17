# proto-merge
Shell script for merging a set of protobuf files
## Introduction

Usage: $0 [*.proto path with the api definition]
$0 basedir/././file.proto

## EXIT CODES
0 - Success

97 - Nothing to merge

98 - Import file don't exist

99 - File don't exist or isn't a proto