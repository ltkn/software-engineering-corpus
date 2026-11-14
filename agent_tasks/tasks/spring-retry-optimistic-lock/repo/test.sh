#!/bin/sh
# Starts the local PostgreSQL if needed, then runs the tests offline.
set -e
pg-up
mvn -o -q -B test
