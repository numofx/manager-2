.PHONY: test fork verify

test:
	@forge test --no-match-path "test/fork/**"

fork:
	@set -a; [ -f .env ] && . ./.env; set +a; \
	if [ -z "$$MAINNET_RPC" ]; then \
		echo "MAINNET_RPC is not set. Example: MAINNET_RPC=... make fork"; \
		exit 1; \
	fi; \
	forge test --match-path "test/fork/**"

verify:
	@grep -n 'forge test' Makefile
	@make -n test
