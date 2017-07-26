ifndef PREFIX
  PREFIX=/usr/local
endif

install:
	install -Dm755 clerk_fzf $(DESTDIR)$(PREFIX)/bin/clerk_fzf
	install -Dm644 tmux.clerk $(DESTDIR)/etc/clerk/tmux.conf
	install -Dm644 clerk_fzf.conf $(DESTDIR)/etc/clerk_fzf.conf

