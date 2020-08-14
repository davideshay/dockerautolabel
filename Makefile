STACK_PREFIX=dal
MAIN_SERVICE=dockerautolabel

.PHONY: build push deploy listen stop

build:
	docker buildx bake --set *.platform=linux/arm64,linux/amd64

push:
	docker buildx bake --set *.platform=linux/arm64,linux/amd64 --push

deploy:
	docker stack deploy -c docker-compose.yml $(STACK_PREFIX)

stop:
	docker stack rm $(STACK_PREFIX)

listen:
	docker service logs -f $(STACK_PREFIX)_$(MAIN_SERVICE)
