# Ed.Love
... is an emacs-like text editor implemented in Lua + Love2d.

This follows Kartik Agaram's principles of Freewheeling Apps and includes the same dynamic lua modules.
See:
 - https://git.sr.ht/~akkartik/
 - https://akkartik.name/freewheeling-apps


## Inspiration:

```text
MG(1)    BSD General Commands Manual    MG(1)

NAME
     mg — emacs-like text editor

SYNOPSIS
     mg [-nR] [-b file] [-f mode] [-u file]
        [+number] [file ...]

DESCRIPTION
     mg is intended to be a small, fast, and
     portable editor for people who can't (or
     don't want to) run emacs for one reason
     or another, or are not familiar with the
     vi(1) editor.  It is compatible with
     emacs because there shouldn't be any
     reason to learn more editor types than
     emacs or vi(1).
```

# Dependencies

0. Lua -- Lua 5.1.5  Copyright (C) 1994-2012 Lua.org, PUC-Rio
1. Love2d -- LOVE 11.4 (Mysterious Mysteries)
3. LuaRocks -- module  deployment system
       for Lua
4. LuaFormatter: `luarocks install --server=https://luarocks.org/dev luaformatter`
