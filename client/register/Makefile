prefix ?= /usr

all:

install:
	mkdir -p $(DESTDIR)$(prefix)/bin
	install -o root -g root -m 755 puavo-client-register \
	  $(DESTDIR)$(prefix)/bin/puavo-client-register

clean:
