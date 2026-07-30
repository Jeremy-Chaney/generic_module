
# Generic Module

This is a generic SystemVerilog Module intended to demonstrate the functionality of features/tools built into this project.

## Functional Description

This module consists of 2 registers which can be synchronously updated. The module also supports an APB Interface to access internal configuration registers and an Interrupt handler.

## Clocks

| Name  | Frequency | Description   |
|-------|-----------|---------------|
| `clk` | Any       | used for APB Interface and all functional synchronous logic within the module |

## Resets

| Name      | Associated Clock  | Description   |
|-----------|-------------------|---------------|
| `reset_n` | Async             | Resets all registers within this module |

## Schematic

![Schematic of the generic block](../schematics/web_trace/generic_module.synth.svg)

<!-- pagebreak -->
