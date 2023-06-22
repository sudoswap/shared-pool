# Shared Pool for Sudoswap

Shared Sudoswap pair using the XYK curve that represents liquidity shares using an ERC20 token. Performs fractional swap during redemption to ensure only whole NFTs are withdrawn.

## Installation

To install with [Foundry](https://github.com/gakonst/foundry):

```
forge install sudoswap/shared-pool
```

## Local development

This project uses [Foundry](https://github.com/gakonst/foundry) as the development framework.

### Dependencies

```
forge install
```

### Compilation

```
forge build
```

### Testing

```
forge test
```

### Contract deployment

Please create a `.env` file before deployment. An example can be found in `.env.example`.

#### Dryrun

```
forge script script/Deploy.s.sol -f [network]
```

### Live

```
forge script script/Deploy.s.sol -f [network] --verify --broadcast
```