PREFIX=install

all:
	gprbuild -p -P posix_shell -XBUILD=prod

readline/libreadline.a: readline/Makefile
	cd readline && make

readline/Makefile:
	cd readline && ./configure --disable-shared --build=i686-pc-mingw32 --prefix=`pwd`/readline-install

check:
	(PATH=`cd $(PREFIX); pwd`/bin:$${PATH} && export PATH && cd testsuite && python ./testsuite.py)

.PHONY: install
install:
	mkdir -p $(PREFIX)
	mkdir -p $(PREFIX)/etc
	cp -p -r gnutools/* $(PREFIX)/
	cp -r etc/* $(PREFIX)/etc
	cp -p obj/prod/no-cov/no-gmem/gsh.exe $(PREFIX)/bin/sh.exe
	cp -p obj/prod/no-cov/no-gmem/gsh.exe $(PREFIX)/bin/gsh.exe

clean:
	-rm -rf obj/*
