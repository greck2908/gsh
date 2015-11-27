GSH - A POSIX shell for Windows
===============================

General Information
-------------------

GSH is an implementation of a [POSIX shell](http://pubs.opengroup.org/onlinepubs/9699919799/)
developed for the Windows platform.

The aim of the project is to provide an efficient UNIX shell
instantiation for Windows, for non interactive usage.

GSH can be used to compile projects depending on autotools, UNIX make,...
As it targets specifically Windows platform, GSH differs significantly
from the most used ones such as bash, zsh. Among others, its implementation
does not depend on the ['fork system call'](https://en.wikipedia.org/wiki/Fork_%28system_call%29)
and doesn't emulate that system call (as it's done on Cygwin).
This allows better compiling performance (the build times can be up to 3 or
4 times faster than builds performed by projects such as Cygwin).

Build & Installation
--------------------

Run:

    $ make
    $ make install PREFIX=<target directory>

Alternatively to just compile the `gsh` binary you can do:

    $ gprbuild -p -P posix_shell

License
-------

All files are provided under terms of the
[GNU General Public License version 3](http://www.gnu.org/licenses/gpl-3.0.en.html).

The project includes fragments of other projects with licenses compatible
with the GNU General Public License version 3:

* [`src/readline`](src/readline) contains the source of the
  [GNU readline library](https://cnswww.cns.cwru.edu/php/chet/readline/rltop.html)
* [`src/gnulib`](src/gnulib) contains part of the
  [GNU Portability Library](https://www.gnu.org/software/gnulib/)
* [`lua/src`](lua/src) contains the sources of [Lua 5.2](http://www.lua.org/)
* [`gnutools`](gnutools) contains some executables from
  [GNUWin](http://gnuwin32.sourceforge.net/)
* [`os/src/ddk`](os/src/ddk) contains the DDK part of the
  [mingw-w64](http://mingw-w64.org/doku.php) project
