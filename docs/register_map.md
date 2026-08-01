# Register Map

This file is auto-generated from scripts/register_map.csv.

## Control (offset 0x00000000)

| Field | Bits | Access | Reset | Description |
|---|---|---|---|---|
| `data_switch_cfg` | `0` | RW | `0x0` | Routes data through local path (0) or submodule path (1) |

## Status (offset 0x00000004)

| Field | Bits | Access | Reset | Description |
|---|---|---|---|---|
| `status_data` | `1+WIDTH-1:1` | RO | `0x0` | Live status bits sourced from status_data |
| `switch_status` | `0` | RO | `0x0` | Reflects the current data_switch_cfg mode |

## Generic Config (offset 0x00000008)

| Field | Bits | Access | Reset | Description |
|---|---|---|---|---|
| `generic_config` | `31:0` | RW | `0x0` | Generic configuration register |

## Interrupt Status (offset 0x0000000C)

| Field | Bits | Access | Reset | Description |
|---|---|---|---|---|
| `irq_event` | `0` | W1C | `0x0` | Interrupt event flag set by hardware and cleared by writing 1 |
