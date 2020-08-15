STACK_PREFIX=dal
MAIN_SERVICE=dockerautolabel
COMPOSE_FILE=docker-compose.yml
PUBLISH_VERSION=2

.PHONY: build push deploy listen stop

build:
	docker buildx bake --set *.platform=linux/arm64,linux/amd64 -f $(COMPOSE_FILE)

push:
	docker buildx build --push --tag davideshay/dockerautolabel:latest --platform linux/amd64,linux/arm64 .
	docker buildx build --push --tag davideshay/dockerautolabel:$(PUBLISH_VERSION) --platform linux/amd64,linux/arm64 .

deploy:
	docker stack deploy -c $(COMPOSE_FILE) $(STACK_PREFIX)

stop:
	docker stack rm $(STACK_PREFIX)

listen:
	docker service logs -f $(STACK_PREFIX)_$(MAIN_SERVICE)
