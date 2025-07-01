#!make

SHELL=bash

run: clean
	love . blog.txt

clean:
	find . -name '*~' -delete
	find . -name '*#*' -delete

check:
	luacheck .
