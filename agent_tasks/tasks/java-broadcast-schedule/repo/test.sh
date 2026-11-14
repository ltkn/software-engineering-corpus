#!/bin/sh
set -e
rm -rf out && mkdir out
javac -d out -cp /opt/junit.jar $(find src test -name '*.java')
java -jar /opt/junit.jar execute -cp out --scan-class-path --disable-banner
