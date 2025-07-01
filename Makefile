#!make

SHELL=bash

run: clean
	love . article.txt

clean:
	find . -name '*~' -delete
	find . -name '*#*' -delete

check:
	luacheck .
sudo luarocks install --server=https://luarocks.org/dev luaformatter
