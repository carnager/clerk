ifndef PREFIX
  PREFIX=/usr/local
endif

install:
	install -Dm755 clerk_fzf $(DESTDIR)$(PREFIX)/bin/clerk_fzf
	install -Dm755 clerk_update $(DESTDIR)$(PREFIX)/bin/clerk_update
	install -Dm755 clerk_starter $(DESTDIR)$(PREFIX)/bin/clerk_starter
	install -Dm755 clerk_help $(DESTDIR)$(PREFIX)/bin/clerk_help
	install -Dm644 tmux.clerk $(DESTDIR)/etc/clerk/tmux.conf
	install -Dm644 clerk_fzf.conf $(DESTDIR)/etc/clerk_fzf.conf

