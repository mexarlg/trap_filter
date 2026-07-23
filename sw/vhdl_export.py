"""
Stimulus export for the VHDL testbench.

Dumps input samples, the ideal shaper output, and a 1-bit sync
pulse to a text file that the VHDL testbench reads.
"""

import os

def export_for_vhdl(noisy, y_ref, data_width=14, out_width=15,
                    in_signed=False, out_signed=True,
                    sync_indices=None, filename="stimulus.txt"):
    """
    Dump input samples + ideal output + a 1-bit sync pulse for the VHDL testbench.
    """
    def clamp(v, width, signed):
        v = int(round(v))
        if signed:
            lo, hi = -(1 << (width - 1)), (1 << (width - 1)) - 1
        else:
            lo, hi = 0, (1 << width) - 1
        return max(lo, min(hi, v))

    n = min(len(noisy), len(y_ref))

    # Give a pulse on selected index for synchronization
    if sync_indices is None:
        sync_indices = [0]
    sync_set = {i for i in sync_indices if 0 <= i < n}

    # Write into a .txt
    with open(filename, "w") as f:
        f.write(f"# n={n} in_w={data_width} out_w={out_width} "
                f"in_signed={int(in_signed)} out_signed={int(out_signed)}\n")
        for i in range(n):
            xi   = clamp(noisy[i], data_width, in_signed)
            yi   = clamp(y_ref[i], out_width,  out_signed)
            sync = 1 if i in sync_set else 0
            f.write(f"{xi} {yi} {sync}\n")
    print(f"wrote {n} samples to {filename} ")

def export_pulse_mem(samples, filename="pulse_data_pkg.vhd",
                      package_name="pulse_data_pkg",
                      const_name="C_INIT_PULSE",
                      width=14):
    """Write a VHDL package with a ROM init constant from unsigned discretized samples."""
    vals = [int(v) for v in samples]
    depth = len(vals)
    hi = (1 << width) - 1

    for i, v in enumerate(vals):
        if not (0 <= v <= hi):
            raise ValueError(f"sample {i} = {v} out of range [0, {hi}]")

    body = ",\n".join(f'        "{format(v, f"0{width}b")}"' for v in vals)

    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "pkg")
    out_dir = os.path.normpath(out_dir)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, filename)

    with open(path, "w") as f:
        f.write(
f"""library ieee;
use ieee.std_logic_1164.all;

package {package_name} is

    type mem_t is array (0 to {depth - 1}) of std_logic_vector({width - 1} downto 0);

    constant {const_name} : mem_t := (
{body}
    );

end package {package_name};
""")

    return path