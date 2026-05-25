.PHONY: build

#: Code formatting
fmt:
	flutter format --fix lib/

#: Analyzes the project's Dart source code
lint:
	flutter analyze lib/

#: Build the web app
build:
	flutter build web -v --release --no-tree-shake-icons

#: Serve the web app
serve:
	cd build/web && npx serve

#: Deploy to surge.sh
deploy:
	surge build/web --domain https://ionicons.ez-connect.net
