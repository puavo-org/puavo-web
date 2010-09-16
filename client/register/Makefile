prefix ?= /usr

all:

install:
	mkdir -p $(DESTDIR)$(prefix)/bin
	install -o root -g root -m 755 puavodevices-client-register \
	  $(DESTDIR)$(prefix)/bin/puavodevices-client-register

clean:
