ifndef PREFIX
  PREFIX=/usr/local
endif

install:
	install -Dm755 clerk $(DESTDIR)$(PREFIX)/bin/clerk
	install -Dm755 clerk_helper $(DESTDIR)$(PREFIX)/bin/clerk_helper
	install -Dm644 config.clerk $(DESTDIR)$(PREFIX)/share/doc/clerk/config.example
	install -Dm644 config.clerk $(DESTDIR)/etc/clerk.conf
	install -Dm644 README.md $(DESTDIR)$(PREFIX)/share/doc/clerk/README.md
	install -Dm755 sticker_import.sh $(DESTDIR)$(PREFIX)/share/doc/clerk/sticker_import.sh

