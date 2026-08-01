#!/usr/bin/env python3
"""Generate rtl/config_registers.sv and docs/register_map.md from scripts/register_map.csv."""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

VALID_ACCESS = {"RO", "RW", "W1C"}
WIDTH_TOKEN = "WIDTH"
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
DEFAULT_CSV = REPO_ROOT / "scripts" / "register_map.csv"
DEFAULT_SV_OUT = REPO_ROOT / "rtl" / "config_registers.sv"
DEFAULT_MD_OUT = REPO_ROOT / "docs" / "register_map.md"


@dataclass(frozen=True)
class FieldRow:
    register: str
    address: int
    field: str
    lsb: int
    width_expr: str
    access: str
    reset: int
    description: str
    bind: str
    hw_set: str

    @property
    def width_is_param(self) -> bool:
        return self.width_expr == WIDTH_TOKEN

    @property
    def width_int(self) -> Optional[int]:
        if self.width_is_param:
            return None
        return int(self.width_expr)

    @property
    def msb_expr(self) -> str:
        if self.width_is_param:
            if self.lsb == 0:
                return f"{WIDTH_TOKEN}-1"
            return f"{self.lsb}+{WIDTH_TOKEN}-1"
        assert self.width_int is not None
        return str(self.lsb + self.width_int - 1)

    @property
    def sv_range(self) -> str:
        width_int = self.width_int
        if width_int == 1:
            return f"[{self.lsb}]"
        if self.width_is_param:
            return f"[{self.msb_expr}:{self.lsb}]"
        return f"[{self.lsb + width_int - 1}:{self.lsb}]"


@dataclass(frozen=True)
class RegisterDef:
    name: str
    address: int
    fields: Tuple[FieldRow, ...]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate config_registers.sv and register markdown docs from CSV"
    )
    parser.add_argument(
        "--csv",
        default=str(DEFAULT_CSV),
        help="Path to register map CSV input",
    )
    parser.add_argument(
        "--sv-out",
        default=str(DEFAULT_SV_OUT),
        help="Path to generated SystemVerilog module",
    )
    parser.add_argument(
        "--md-out",
        default=str(DEFAULT_MD_OUT),
        help="Path to generated markdown documentation",
    )
    return parser.parse_args()


def sanitize_ident(name: str) -> str:
    out = []
    for ch in name:
        if ch.isalnum() or ch == "_":
            out.append(ch.lower())
        else:
            out.append("_")
    ident = "".join(out).strip("_")
    if not ident:
        raise ValueError(f"Identifier is empty after sanitizing: {name!r}")
    if ident[0].isdigit():
        ident = f"r_{ident}"
    return ident


def normalize_name(name: str) -> str:
    stripped = name.strip()
    if not stripped:
        raise ValueError("Register and field names must be non-empty")
    return stripped


def parse_width_expr(raw: str) -> str:
    value = raw.strip()
    if not value:
        raise ValueError("width must be provided")
    if value.upper() == WIDTH_TOKEN:
        return WIDTH_TOKEN
    width = int(value, 10)
    if width < 1 or width > 32:
        raise ValueError(f"width must be in 1..32 or WIDTH, got {value!r}")
    return str(width)


def parse_reset(raw: str) -> int:
    value = raw.strip()
    if not value:
        return 0
    return int(value, 0)


def parse_access(raw: str) -> str:
    access = raw.strip().upper()
    if access not in VALID_ACCESS:
        raise ValueError(f"access must be one of {sorted(VALID_ACCESS)}, got {raw!r}")
    return access


def parse_bind(raw: Optional[str]) -> str:
    return (raw or "").strip()


def parse_hw_set(raw: Optional[str]) -> str:
    return (raw or "").strip()


def read_rows(csv_path: Path) -> List[FieldRow]:
    required = {
        "register_name",
        "address",
        "field_name",
        "lsb",
        "width",
        "access",
        "reset",
        "description",
        "bind",
        "hw_set",
    }
    rows: List[FieldRow] = []
    with csv_path.open("r", encoding="ascii", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError("CSV is missing a header row")
        missing = required.difference({f.strip() for f in reader.fieldnames})
        if missing:
            raise ValueError(f"CSV missing required columns: {sorted(missing)}")

        for line_idx, raw_row in enumerate(reader, start=2):
            try:
                register = normalize_name(raw_row["register_name"])
                address = int(raw_row["address"].strip(), 0)
                field = normalize_name(raw_row["field_name"])
                lsb = int(raw_row["lsb"].strip(), 10)
                width_expr = parse_width_expr(raw_row["width"])
                access = parse_access(raw_row["access"])
                reset = parse_reset(raw_row["reset"])
                description = raw_row["description"].strip()
                bind = parse_bind(raw_row["bind"])
                hw_set = parse_hw_set(raw_row["hw_set"])
            except Exception as exc:
                raise ValueError(f"CSV line {line_idx}: {exc}") from exc

            if address % 4 != 0:
                raise ValueError(f"CSV line {line_idx}: address must be 4-byte aligned")
            if lsb < 0 or lsb > 31:
                raise ValueError(f"CSV line {line_idx}: lsb must be in 0..31")
            if width_expr != WIDTH_TOKEN:
                width = int(width_expr)
                if lsb + width > 32:
                    raise ValueError(
                        f"CSV line {line_idx}: bit range [{lsb + width - 1}:{lsb}] exceeds 31:0"
                    )
                max_reset = (1 << width) - 1
                if reset < 0 or reset > max_reset:
                    raise ValueError(
                        f"CSV line {line_idx}: reset {reset} does not fit width {width}"
                    )
            elif lsb != 0 and access == "W1C":
                raise ValueError(
                    f"CSV line {line_idx}: WIDTH token with W1C is not supported in this generator"
                )

            if access == "W1C" and not hw_set:
                raise ValueError(
                    f"CSV line {line_idx}: W1C fields require hw_set signal name"
                )

            if bind:
                if ":" not in bind:
                    raise ValueError(
                        f"CSV line {line_idx}: bind must be empty or kind:name"
                    )
                bind_kind, bind_name = bind.split(":", 1)
                bind_kind = bind_kind.strip()
                bind_name = bind_name.strip()
                if bind_kind not in {"output", "input", "input_vec"}:
                    raise ValueError(
                        f"CSV line {line_idx}: bind kind must be output/input/input_vec"
                    )
                if not bind_name:
                    raise ValueError(f"CSV line {line_idx}: bind signal name is empty")
                if bind_kind == "input_vec" and width_expr not in {WIDTH_TOKEN} and int(width_expr) < 2:
                    raise ValueError(
                        f"CSV line {line_idx}: input_vec binding requires width >= 2 or WIDTH"
                    )

            rows.append(
                FieldRow(
                    register=register,
                    address=address,
                    field=field,
                    lsb=lsb,
                    width_expr=width_expr,
                    access=access,
                    reset=reset,
                    description=description,
                    bind=bind,
                    hw_set=hw_set,
                )
            )

    return rows


def validate_rows(rows: Sequence[FieldRow]) -> List[RegisterDef]:
    if not rows:
        raise ValueError("CSV has no register fields")

    grouped: Dict[Tuple[str, int], List[FieldRow]] = {}
    for row in rows:
        key = (row.register, row.address)
        grouped.setdefault(key, []).append(row)

    register_defs: List[RegisterDef] = []
    seen_field_keys: set[Tuple[str, str]] = set()
    output_bind_signals: Dict[str, Tuple[str, str]] = {}

    for (reg_name, address), fields in grouped.items():
        used_bits = [False] * 32

        for field in fields:
            field_key = (reg_name, field.field)
            if field_key in seen_field_keys:
                raise ValueError(f"Duplicate field name within register: {reg_name}.{field.field}")
            seen_field_keys.add(field_key)

            if field.width_is_param:
                if field.lsb != 0 and field.lsb != 1:
                    raise ValueError(
                        f"WIDTH-based field {reg_name}.{field.field} must start at bit 0 or 1"
                    )
            else:
                width = field.width_int
                assert width is not None
                for bit in range(field.lsb, field.lsb + width):
                    if used_bits[bit]:
                        raise ValueError(
                            f"Bit overlap in {reg_name} at bit {bit} for field {field.field}"
                        )
                    used_bits[bit] = True

            if field.bind.startswith("output:"):
                bind_signal = field.bind.split(":", 1)[1].strip()
                existing = output_bind_signals.get(bind_signal)
                if existing is not None and existing != (reg_name, field.field):
                    raise ValueError(
                        f"Output signal {bind_signal} cannot bind to multiple fields"
                    )
                output_bind_signals[bind_signal] = (reg_name, field.field)

        register_defs.append(
            RegisterDef(
                name=reg_name,
                address=address,
                fields=tuple(sorted(fields, key=lambda f: f.lsb)),
            )
        )

    return sorted(register_defs, key=lambda r: (r.address, r.name.lower()))


def sv_addr_const(reg_name: str) -> str:
    return f"{sanitize_ident(reg_name).upper()}_ADDR"


def sv_reg_var(reg_name: str) -> str:
    return f"{sanitize_ident(reg_name)}_reg"


def reg_has_writable_fields(reg: RegisterDef) -> bool:
    return any(field.access in {"RW", "W1C"} for field in reg.fields)


def render_port_declarations(registers: Sequence[RegisterDef]) -> Tuple[List[str], Dict[str, str], Dict[str, str]]:
    outputs: Dict[str, str] = {}
    inputs: Dict[str, str] = {}
    w1c_sets: Dict[str, str] = {}

    for reg in registers:
        for field in reg.fields:
            if field.bind:
                kind, signal = [part.strip() for part in field.bind.split(":", 1)]
                if kind == "output":
                    if signal in outputs:
                        raise ValueError(f"Duplicate output bind signal: {signal}")
                    width_decl = "" if field.width_int == 1 else f" [{field.msb_expr}:0]"
                    outputs[signal] = width_decl
                elif kind == "input":
                    if signal in outputs:
                        continue
                    if signal in inputs:
                        continue
                    inputs[signal] = ""
                elif kind == "input_vec":
                    if signal in outputs:
                        continue
                    if signal in inputs:
                        continue
                    width_decl = f" [{WIDTH_TOKEN}-1:0]" if field.width_is_param else f" [{field.width_int - 1}:0]"
                    inputs[signal] = width_decl

            if field.access == "W1C":
                sig = field.hw_set
                if not sig:
                    continue
                if sig in w1c_sets:
                    continue
                if field.width_is_param:
                    raise ValueError("WIDTH-based W1C fields are not supported")
                width_int = field.width_int
                assert width_int is not None
                w1c_sets[sig] = "" if width_int == 1 else f" [{width_int - 1}:0]"

    port_lines: List[str] = []
    for signal in sorted(outputs):
        port_lines.append(f"    output logic{outputs[signal]}        {signal},")
    for signal in sorted(inputs):
        port_lines.append(f"    input  logic{inputs[signal]}        {signal},")
    for signal in sorted(w1c_sets):
        port_lines.append(f"    input  logic{w1c_sets[signal]}        {signal},")

    return port_lines, outputs, w1c_sets


def render_reset_value(reg: RegisterDef) -> str:
    value = 0
    for field in reg.fields:
        if field.access in {"RW", "W1C"}:
            width = field.width_int
            if width is None:
                continue
            value |= (field.reset & ((1 << width) - 1)) << field.lsb
    return f"32'h{value:08X}"


def render_sv(registers: Sequence[RegisterDef]) -> str:
    port_lines, outputs, _w1c_sets = render_port_declarations(registers)

    lines: List[str] = []
    lines.append("// -----------------------------------------------------------------------------")
    lines.append("// AUTO-GENERATED FILE. DO NOT EDIT DIRECTLY.")
    lines.append("// Generated by scripts/gen_register_artifacts.py from scripts/register_map.csv")
    lines.append("// -----------------------------------------------------------------------------")
    lines.append("module config_registers #(")
    lines.append("    parameter int WIDTH = 8")
    lines.append(") (")
    lines.append("    input  logic                clk,")
    lines.append("    input  logic                reset_n,")
    lines.append("    input  logic [31:0]         paddr,")
    lines.append("    input  logic                psel,")
    lines.append("    input  logic                penable,")
    lines.append("    input  logic                pwrite,")
    lines.append("    input  logic [31:0]         pwdata,")
    lines.append("    output logic [31:0]         prdata,")
    lines.append("    output logic                pready,")
    lines.append("    output logic                pslverr,")

    if port_lines:
        lines.extend(port_lines[:-1])
        lines.append(port_lines[-1].rstrip(","))
    else:
        lines[-1] = lines[-1].rstrip(",")

    lines.append(");")
    lines.append("")

    for reg in registers:
        lines.append(
            f"    localparam logic [31:0] {sv_addr_const(reg.name):<22} = 32'h{reg.address:08X};"
        )
    lines.append("")

    lines.append("    assign pready  = 1'b1;")
    lines.append("    assign pslverr = 1'b0;")
    lines.append("")

    for reg in registers:
        if reg_has_writable_fields(reg):
            lines.append(f"    logic [31:0] {sv_reg_var(reg.name)};")
    if any(reg_has_writable_fields(reg) for reg in registers):
        lines.append("")

    # Output binds map to backing bits.
    for reg in registers:
        for field in reg.fields:
            if field.bind.startswith("output:"):
                signal = field.bind.split(":", 1)[1].strip()
                lines.append(
                    f"    assign {signal} = {sv_reg_var(reg.name)}{field.sv_range};"
                )
    if outputs:
        lines.append("")

    # Sequential block for writable fields and W1C hardware set.
    if any(reg_has_writable_fields(reg) for reg in registers):
        lines.append("    always_ff @(posedge clk or negedge reset_n) begin")
        lines.append("        if (!reset_n) begin")
        for reg in registers:
            if reg_has_writable_fields(reg):
                lines.append(
                    f"            {sv_reg_var(reg.name)} <= {render_reset_value(reg)};"
                )
        lines.append("        end else begin")
        lines.append("            if (psel && penable && pwrite) begin")
        lines.append("                unique case (paddr)")

        for reg in registers:
            if not reg_has_writable_fields(reg):
                continue
            lines.append(f"                    {sv_addr_const(reg.name)}: begin")
            for field in reg.fields:
                target = f"{sv_reg_var(reg.name)}{field.sv_range}"
                if field.access == "RW":
                    lines.append(f"                        {target} <= pwdata{field.sv_range};")
                elif field.access == "W1C":
                    lines.append(
                        f"                        {target} <= {target} & ~pwdata{field.sv_range};"
                    )
            lines.append("                    end")
        lines.append("                    default: begin end")
        lines.append("                endcase")
        lines.append("            end")

        lines.append("")
        lines.append("            // Hardware-set path for W1C fields. HW-set takes priority over SW-clear.")
        for reg in registers:
            for field in reg.fields:
                if field.access != "W1C":
                    continue
                target = f"{sv_reg_var(reg.name)}{field.sv_range}"
                lines.append(f"            {target} <= {target} | {field.hw_set};")
        lines.append("        end")
        lines.append("    end")
        lines.append("")

    # Read words with RO overlays.
    for reg in registers:
        lines.append(f"    logic [31:0] {sanitize_ident(reg.name)}_rd;")
    lines.append("")

    lines.append("    always_comb begin")
    for reg in registers:
        base = sv_reg_var(reg.name) if reg_has_writable_fields(reg) else "32'h00000000"
        lines.append(f"        {sanitize_ident(reg.name)}_rd = {base};")

        for field in reg.fields:
            if field.access != "RO":
                continue
            if field.bind.startswith("input:"):
                signal = field.bind.split(":", 1)[1].strip()
                lines.append(
                    f"        {sanitize_ident(reg.name)}_rd{field.sv_range} = {signal};"
                )
            elif field.bind.startswith("input_vec:"):
                signal = field.bind.split(":", 1)[1].strip()
                if field.width_is_param:
                    lines.append(
                        f"        for (int i = 0; i < WIDTH; i++) begin"
                    )
                    lines.append(
                        f"            if ((i + {field.lsb}) < 32) begin"
                    )
                    lines.append(
                        f"                {sanitize_ident(reg.name)}_rd[i + {field.lsb}] = {signal}[i];"
                    )
                    lines.append("            end")
                    lines.append("        end")
                else:
                    width = field.width_int
                    assert width is not None
                    lines.append(
                        f"        {sanitize_ident(reg.name)}_rd{field.sv_range} = {signal}[{width - 1}:0];"
                    )
        lines.append("")

    lines.append("        prdata = '0;")
    lines.append("        if (psel && !pwrite) begin")
    lines.append("            unique case (paddr)")
    for reg in registers:
        lines.append(
            f"                {sv_addr_const(reg.name)}: prdata = {sanitize_ident(reg.name)}_rd;"
        )
    lines.append("                default: prdata = '0;")
    lines.append("            endcase")
    lines.append("        end")
    lines.append("    end")
    lines.append("endmodule")
    lines.append("")

    return "\n".join(lines)


def escape_md(value: str) -> str:
    return value.replace("|", "\\|")


def render_markdown(registers: Sequence[RegisterDef]) -> str:
    lines: List[str] = []
    lines.append("# Register Map")
    lines.append("")
    lines.append("This file is auto-generated from scripts/register_map.csv.")
    lines.append("")

    for reg in registers:
        lines.append(f"## {reg.name} (offset 0x{reg.address:08X})")
        lines.append("")
        lines.append("| Field | Bits | Access | Reset | Description |")
        lines.append("|---|---|---|---|---|")
        for field in sorted(reg.fields, key=lambda f: f.lsb, reverse=True):
            bits = field.sv_range.replace("[", "").replace("]", "")
            lines.append(
                "| "
                + " | ".join(
                    [
                        f"`{escape_md(field.field)}`",
                        f"`{bits}`",
                        field.access,
                        f"`0x{field.reset:X}`",
                        escape_md(field.description),
                    ]
                )
                + " |"
            )
        lines.append("")

    return "\n".join(lines)


def resolve_path(path_value: str, repo_root: Path) -> Path:
    path = Path(path_value)
    if path.is_absolute():
        return path
    return (repo_root / path).resolve()


def write_ascii(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="ascii", newline="\n")


def main() -> int:
    args = parse_args()
    csv_path = resolve_path(args.csv, REPO_ROOT)
    sv_out = resolve_path(args.sv_out, REPO_ROOT)
    md_out = resolve_path(args.md_out, REPO_ROOT)

    rows = read_rows(csv_path)
    registers = validate_rows(rows)

    sv_text = render_sv(registers)
    md_text = render_markdown(registers)

    write_ascii(sv_out, sv_text)
    write_ascii(md_out, md_text)

    print(f"Generated {sv_out} and {md_out} from {csv_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
