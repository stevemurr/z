.PHONY: build install clean

BINARY_NAME=z-beacon
BUILD_DIR=bin
INSTALL_DIR=$(HOME)/.z/bin

build:
	@mkdir -p $(BUILD_DIR)
	go build -o $(BUILD_DIR)/$(BINARY_NAME) ./cmd/z-beacon

install: build
	@mkdir -p $(INSTALL_DIR)
	cp $(BUILD_DIR)/$(BINARY_NAME) $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "Installed $(BINARY_NAME) to $(INSTALL_DIR)"

clean:
	rm -rf $(BUILD_DIR)
