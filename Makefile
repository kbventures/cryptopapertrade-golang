.PHONY: dev test lint migrate migrate-down logs down help

## dev: start Docker services and run the Go server
dev:
	docker-compose up -d
	go run cmd/api/main.go

## test: run all Go tests
test:
	go test ./...

## lint: run golangci-lint
lint:
	golangci-lint run ./...

## migrate: run database migrations (up)
migrate:
	go run cmd/migrate/main.go up

## migrate-down: roll back the last migration
migrate-down:
	go run cmd/migrate/main.go down

## logs: tail Docker service logs
logs:
	docker-compose logs -f

## down: stop all Docker services
down:
	docker-compose down

## help: list available commands
help:
	@grep -E '^## ' Makefile | sed 's/## /  make /'
