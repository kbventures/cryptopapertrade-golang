.PHONY: dev test lint migrate mobile logs down help

SERVER_DIR := apps/server
MOBILE_DIR := apps/mobile

## dev: start Docker services and run the Go server
dev:
	docker-compose up -d
	cd $(SERVER_DIR) && go run cmd/api/main.go

## mobile: start Expo dev server
mobile:
	cd $(MOBILE_DIR) && npx expo start

## test: run all Go tests
test:
	go test ./$(SERVER_DIR)/...

## lint: run golangci-lint on the Go server
lint:
	golangci-lint run ./$(SERVER_DIR)/...

## migrate: run database migrations (up)
migrate:
	cd $(SERVER_DIR) && go run cmd/migrate/main.go up

## migrate-down: roll back the last migration
migrate-down:
	cd $(SERVER_DIR) && go run cmd/migrate/main.go down

## logs: tail Docker service logs
logs:
	docker-compose logs -f

## down: stop all Docker services
down:
	docker-compose down

## help: list available commands
help:
	@grep -E '^## ' Makefile | sed 's/## /  make /'
