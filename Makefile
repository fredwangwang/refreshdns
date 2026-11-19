.PHONY: build dmg install uninstall clean

build:
	@chmod +x scripts/build.sh scripts/make_dmg.sh scripts/uninstall.sh
	@./scripts/build.sh

dmg: build
	@./scripts/make_dmg.sh

install: build
	@echo "==> Installing RefreshDNS.app to /Applications..."
	@rm -rf /Applications/RefreshDNS.app
	@cp -R build/RefreshDNS.app /Applications/RefreshDNS.app
	@echo "==> Installed: /Applications/RefreshDNS.app"

uninstall:
	@chmod +x scripts/uninstall.sh
	@./scripts/uninstall.sh

clean:
	@rm -rf build
