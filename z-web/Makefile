.PHONY: all build clean dev install

# Default target
all: build

# Build the complete application
build: build-frontend build-backend

# Build frontend (output to cmd/z-web/dist)
build-frontend:
	cd web && npm install && npm run build

# Build Go backend
build-backend:
	cd cmd/z-web && go build -o ../../bin/z-web .

# Development mode - run both frontend and backend
dev:
	@echo "Starting development servers..."
	@echo "Frontend: http://localhost:5173"
	@echo "Backend:  http://localhost:7680"
	@echo ""
	@(cd web && npm run dev) &
	@(cd cmd/z-web && go run . --host localhost)

# Run just the frontend dev server
dev-frontend:
	cd web && npm run dev

# Run just the backend
dev-backend:
	cd cmd/z-web && go run . --host localhost

# Clean build artifacts
clean:
	rm -rf bin/
	rm -rf cmd/z-web/dist/
	rm -rf web/node_modules/

# Install z-web binary to ~/.z/bin
install: build
	mkdir -p ~/.z/bin
	cp bin/z-web ~/.z/bin/
	@echo "Installed z-web to ~/.z/bin/z-web"

# Download Go dependencies
deps:
	go mod download
	cd web && npm install

# Format code
fmt:
	go fmt ./...

# Run linter
lint:
	go vet ./...
