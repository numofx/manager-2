set shell := ["bash", "-eu", "-o", "pipefail", "-c"]
set dotenv-load := true

# Show available commands
@default:
  just --list

# Compile contracts
build:
  forge build

# Run unit tests only (no fork tests)
test:
  forge test --no-match-path "test/fork/**"

# Run fork tests (requires MAINNET_RPC)
test-fork:
  : "${MAINNET_RPC:?MAINNET_RPC is required for fork tests}"
  forge test --match-path "test/fork/**"

# Run tests matching a path pattern
# Example: just test-match "**/MentoSpotOracleBasic.t.sol"
test-match pattern:
  forge test --match-path "{{pattern}}"

# Deploy core contracts for a chain
# Example: just deploy-core celo
# Example: just deploy-core base
# Optional flags arg can pass extra forge flags, e.g. --verify --slow
# Example: just deploy-core base "--verify --slow"
deploy-core chain flags="":
  case "{{chain}}" in \
    celo) \
      : "${CELO_RPC:?CELO_RPC is required}"; \
      forge script script/celo/DeployCelo.s.sol:DeployCelo --rpc-url "$CELO_RPC" --broadcast {{flags}} ;; \
    base) \
      : "${BASE_RPC:?BASE_RPC is required}"; \
      forge script script/base/DeployBase.s.sol:DeployBase --rpc-url "$BASE_RPC" --broadcast {{flags}} ;; \
    *) echo "Unsupported chain '{{chain}}' (expected: celo|base)"; exit 1 ;; \
  esac

# Configure market wiring for a chain+asset market
# Supported markets:
# - celo usdt-kesm (or usdtkesm)
# - celo full (full ConfigureCelo flow)
# - base ausdc-cngn (or ausdccngn)
# Example: just deploy-market base ausdc-cngn
deploy-market chain asset flags="":
  case "{{chain}}:{{asset}}" in \
    celo:usdt-kesm|celo:usdtkesm) \
      : "${CELO_RPC:?CELO_RPC is required}"; \
      forge script script/celo/ConfigureUSDTKESm.s.sol:ConfigureUSDTKESm --rpc-url "$CELO_RPC" --broadcast {{flags}} ;; \
    celo:full) \
      : "${CELO_RPC:?CELO_RPC is required}"; \
      forge script script/celo/ConfigureCelo.s.sol:ConfigureCelo --rpc-url "$CELO_RPC" --broadcast {{flags}} ;; \
    base:ausdc-cngn|base:ausdccngn) \
      : "${BASE_RPC:?BASE_RPC is required}"; \
      forge script script/base/ConfigureAUSDCCNGN.s.sol:ConfigureAUSDCCNGN --rpc-url "$BASE_RPC" --broadcast {{flags}} ;; \
    *) echo "Unsupported chain/asset '{{chain}}:{{asset}}'"; exit 1 ;; \
  esac

# Deploy/register FYToken series for a chain+asset market
# Supported markets:
# - celo usdt-kesm (or usdtkesm)
# - base ausdc-cngn (or ausdccngn)
# Example: just deploy-series base ausdc-cngn
deploy-series chain asset flags="":
  case "{{chain}}:{{asset}}" in \
    celo:usdt-kesm|celo:usdtkesm) \
      : "${CELO_RPC:?CELO_RPC is required}"; \
      forge script script/celo/DeployFYKESm.s.sol:DeployFYKESm --rpc-url "$CELO_RPC" --broadcast {{flags}} ;; \
    base:ausdc-cngn|base:ausdccngn) \
      : "${BASE_RPC:?BASE_RPC is required}"; \
      forge script script/base/DeployFYCNGNMay2026.s.sol:DeployFYCNGNMay2026 --rpc-url "$BASE_RPC" --broadcast {{flags}} ;; \
    *) echo "Unsupported chain/asset '{{chain}}:{{asset}}'"; exit 1 ;; \
  esac

# Convenience: run full split flow (core -> market -> series)
# Requires env vars for the chosen chain/asset to already be set.
# Example: just deploy-all base ausdc-cngn
# Example: just deploy-all celo usdt-kesm "--verify --slow"
deploy-all chain asset flags="":
  just deploy-core {{chain}} "{{flags}}"
  just deploy-market {{chain}} {{asset}} "{{flags}}"
  just deploy-series {{chain}} {{asset}} "{{flags}}"
