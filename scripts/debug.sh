#!/usr/bin/env bash

odin run sandbox -sanitize:address -collection:extern=./extern -collection:thorn=./thorn/src -out:build/thorn
