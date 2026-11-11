#!/bin/bash
SRC=$1
DEST=$2
for f in $(ls $SRC); do
  cp $SRC/$f $DEST/
done
echo "backed up"
