URL=http://127.0.0.1:1313

build:
	hugo --minify

clean: 
	rm -r public

run: 
	start "" $(URL)
	hugo server --disableFastRender -D

pull: 
	git pull && git submodule update --remote --merge

push: pull
	git submodule update --remote --merge
	git add . && git commit -m "Update" && git push