"""
Stimulus export for the VHDL testbench.

Dumps input samples, the ideal shaper output, and a 1-bit sync
pulse to a text file that the VHDL testbench reads.
"""


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
