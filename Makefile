# Makefile for building and running a Jekyll site with Docker

# Variables
IMAGE_NAME := jazco-dev
CONTAINER_NAME := jazco-dev
JEKYLL_PORT := 4000
DOCKER_RUN_OPTS := -it --rm --name $(CONTAINER_NAME) -p $(JEKYLL_PORT):4000 -v "$(PWD):/srv/jekyll"

# Targets

build:
	@echo "Building Docker image..."
	@docker build -t $(IMAGE_NAME) .

run:
	@echo "Running Docker container..."
	@docker run $(DOCKER_RUN_OPTS) $(IMAGE_NAME)

clean:
	@echo "Stopping and removing container (if exists)..."
	@docker stop $(CONTAINER_NAME) || true
	@docker rm $(CONTAINER_NAME) || true

.PHONY: build run clean
