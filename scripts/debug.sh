#!/usr/bin/env bash

odin run thorn/src -sanatize:address -collection:extern=./extern -collection:thorn=./thorn/src -out:build/thorn
