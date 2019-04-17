all:
	dub build -b release

debug:
	dub build -b debug -f

release:
	dub build -b release -f
