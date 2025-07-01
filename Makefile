#!make

SHELL=bash

run: clean
	love . article.txt

clean:
	find . -name '*~' -delete
	find . -name '*#*' -delete

check:
	luacheck .

deps:
	sudo luarocks install --server=https://luarocks.org/dev luaformatter

fmt:
	/usr/local/bin/lua-format -i ./*.lua ./00*
