# Cozy Safety Module Rewards Manager

A Rewards Manager enables projects to configure stake pools and reward pools for user incentivization.
- Stakers can stake assets in configured stake pools
- Stakers receive rewards from configured reward pools

In the context of [Cozy Safety Modules](https://github.com/Cozy-Finance/cozy-safety-module), a Rewards Manager can be utilized to incentivize Safety Module depositors by allowing them to stake their deposit receipt tokens to receive rewards.

## Development

### Getting Started

This repo is built using [Foundry](https://github.com/gakonst/foundry).

## Definitions and Standards

Definitions of terms used:
- `zoc`: A number with 4 decimals.
- `wad`: A number with 18 decimals.

Throughout the code the following standards are used:
- All token quantities in function inputs and return values are denominated in the same units (i.e. same number of decimals) as the underlying `asset` of the related asset pool.

