PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin

all:
	@echo "Run 'sudo make install' to install mstream."

install:
	@echo "Installing mstream to $(DESTDIR)$(BINDIR)..."
	@mkdir -p $(DESTDIR)$(BINDIR)
	@install -Dm755 mstream.sh $(DESTDIR)$(BINDIR)/mstream
	@echo "mstream has been successfully installed!"

uninstall:
	@echo "Uninstalling mstream from $(DESTDIR)$(BINDIR)..."
	@rm -f $(DESTDIR)$(BINDIR)/mstream
	@echo "mstream has been uninstalled."
