"""
periodic_pulse_window.py
========================
Generate a *periodic* 14-bit ADC stimulus window for a VHDL pulse-shaper testbench.

Window layout (one period):

    |<-lead->|  P1  |<--- gap: decay to baseline --->|  P2  P3  |<-- tail: decay to baseline -->|
                                                      |<-sep->|

Author: Script generated with help of AI.

"""

import numpy as np

# ----------------------------------------------------------------------
# ADC definition
# ----------------------------------------------------------------------
ADC_BITS = 14
ADC_MAX = (1 << ADC_BITS) - 1        


def quantize_adc(analog):
    """Quantize an analog waveform to unsigned 14-bit ADC codes (0 .. ADC_MAX)."""
    return np.clip(np.round(analog), 0, ADC_MAX).astype(np.int64)


# ----------------------------------------------------------------------
# Pulse shape
# ----------------------------------------------------------------------
def _raw_shape(dt, tau_rise, tau_decay, model="tanh", shift_taus=5.0):
    """Un-normalised pulse shape, zero for dt < 0.

    model="tanh": 0.5*(1+tanh(u/tau_r)) * exp(-u/tau_d), with u = dt - shift*tau_r.
                  The shift makes the truncation at dt=0 harmless: the residual
                  there is 0.5*(1+tanh(-shift)), i.e. 2.3e-5 for shift=5.
    model="exp":  (1 - exp(-dt/tau_r)) * exp(-dt/tau_d)  -- exactly causal.
    """
    dt = np.asarray(dt, dtype=float)
    out = np.zeros_like(dt)
    m = dt >= 0.0
    if not np.any(m):
        return out

    if model == "exp":
        d = dt[m]
        out[m] = (1.0 - np.exp(-d / tau_rise)) * np.exp(-d / tau_decay)
    elif model == "tanh":
        u = dt[m] - shift_taus * tau_rise
        out[m] = 0.5 * (1.0 + np.tanh(u / tau_rise)) * np.exp(-u / tau_decay)
    else:
        raise ValueError("model must be 'tanh' or 'exp'")
    return out


def shape_peak(tau_rise, tau_decay, model="tanh", shift_taus=5.0):
    """Numeric (peak_value, time_of_peak) of the un-normalised shape."""
    tmax = max(80.0 * tau_rise, 0.3 * tau_decay)
    tt = np.linspace(0.0, tmax, 200_001)
    ss = _raw_shape(tt, tau_rise, tau_decay, model, shift_taus)
    k = int(np.argmax(ss))
    return float(ss[k]), float(tt[k])


# ----------------------------------------------------------------------
# Periodic pulse train
# ----------------------------------------------------------------------
def _pulse_train(t, T_window, pulses, tau_rise, tau_decay,
                 model="tanh", shift_taus=5.0, norm=1.0,
                 wrap_tails=False, tol=1e-10):
    """Sum of pulses over one window.

    wrap_tails=False (default): the window is self-contained. Every pulse is
        strictly causal and its tail is simply allowed to die out inside the
        window. Sample 0 is exactly the baseline; the window is seamless when
        looped provided the last tail has fallen below half an LSB by the end
        (which is what the automatic tail sizing enforces).

    wrap_tails=True: each tail is additionally folded back to the start of the
        window, making the signal mathematically periodic even if it has not
        settled. Use only if you deliberately want a short window with a
        residual pedestal at t=0.
    """
    y = np.zeros_like(t, dtype=float)

    if not wrap_tails:
        for t0, amp in pulses:
            y += (amp / norm) * _raw_shape(t - t0, tau_rise, tau_decay,
                                           model, shift_taus)
        return y

    ratio = T_window / tau_decay
    n_wrap = int(np.ceil(-np.log(tol) / max(ratio, 1e-12)))
    n_wrap = int(np.clip(n_wrap, 1, 200))
    for t0, amp in pulses:
        dt0 = np.mod(t - t0, T_window)
        scale = amp / norm
        for k in range(n_wrap + 1):
            y += scale * _raw_shape(dt0 + k * T_window,
                                    tau_rise, tau_decay, model, shift_taus)
    return y


# ----------------------------------------------------------------------
# Main generator
# ----------------------------------------------------------------------
def generate_periodic_test_window(
        fs=100e6,                 # sampling rate [Hz]
        tau_rise_s=8e-8,          # rise time constant [s]
        tau_decay_s=2e-5,         # preamp decay time constant [s]
        amp_pct=(35.0, 35.0, 35.0),   # peak amplitude of P1, P2, P3 [% of full scale]
        baseline_pct=6.0,         # DC pedestal [% of full scale]
        noise_sigma_lsb=30.0,     # white noise std dev [LSB]
        noise_offset_lsb=0.0,     # small DC offset on top of baseline [LSB]
        pileup_sep_taus=0.5,      # P2 -> P3 separation, in units of tau_decay
        pileup_sep_s=None,        # ... or directly in seconds (overrides above)
        lead_taus=0.25,           # quiet baseline before P1
        gap_taus=None,            # P1 -> P2 gap; None = auto (decay to noise floor)
        tail_taus=None,           # P3 -> end of window; None = auto
        settle_thresh_lsb=None,   # residual that counts as "baseline reached" [LSB]
                                  # None = 0.5 LSB, i.e. below one quantisation step
        wrap_tails=False,         # see _pulse_train(); leave False
        n_samples=None,           # force a depth (otherwise computed)
        depth_multiple=1,         # round the computed depth up to a multiple of this
        seed=0,
        model="tanh",             # "tanh" (your shape) or "exp" (strictly causal)
        shift_taus=5.0,
        verbose=True):
    """Build one period of the stimulus window.

    Returns a dict with:
        t, clean, noisy      -> arrays (clean/noisy are int64 ADC codes)
        clean_f, noisy_f     -> the same, before quantisation/clipping (float)
        n_samples, Tclk, T_window
        pulse_starts_s / _idx, pulse_peaks_s / _idx, amps_lsb
        headroom, clipping info
    """
    Tclk = 1.0 / fs
    amps = np.asarray(amp_pct, dtype=float) / 100.0 * ADC_MAX
    if amps.size != 3:
        raise ValueError("amp_pct must hold 3 values: (P1, P2, P3)")
    baseline = baseline_pct / 100.0 * ADC_MAX

    # "at baseline" = the deterministic tail is below half a quantisation step
    thr = settle_thresh_lsb if settle_thresh_lsb is not None else 0.5

    peak_val, t_peak = shape_peak(tau_rise_s, tau_decay_s, model, shift_taus)

    # --- timeline ------------------------------------------------------
    sep = pileup_sep_s if pileup_sep_s is not None else pileup_sep_taus * tau_decay_s
    lead = lead_taus * tau_decay_s

    # gap: time for P1 to fall from its peak down to `thr`
    if gap_taus is not None:
        gap = gap_taus * tau_decay_s
    else:
        gap = t_peak + tau_decay_s * np.log(max(amps[0], thr) / (0.5 * thr))

    # tail: same, but starting from the combined pileup peak
    a_pileup = amps[2] + amps[1] * np.exp(-sep / tau_decay_s)
    if tail_taus is not None:
        tail = tail_taus * tau_decay_s
    else:
        tail = t_peak + tau_decay_s * np.log(max(a_pileup, thr) / (0.5 * thr))

    t1 = lead
    t2 = t1 + gap
    t3 = t2 + sep

    if n_samples is None:
        n = int(np.ceil((t3 + tail) / Tclk))
        if depth_multiple > 1:
            n = int(np.ceil(n / depth_multiple) * depth_multiple)
    else:
        n = int(n_samples)

    T_window = n * Tclk
    t = np.arange(n) * Tclk
    pulses = [(t1, amps[0]), (t2, amps[1]), (t3, amps[2])]

    # --- waveform ------------------------------------------------------
    train = _pulse_train(t, T_window, pulses, tau_rise_s, tau_decay_s,
                         model, shift_taus, norm=peak_val,
                         wrap_tails=wrap_tails)

    clean_f = baseline + train
    rng = np.random.default_rng(seed)
    noisy_f = clean_f + noise_offset_lsb + rng.normal(0.0, noise_sigma_lsb, n)

    clean = quantize_adc(clean_f)
    noisy = quantize_adc(noisy_f)

    # --- diagnostics ---------------------------------------------------
    starts_s = np.array([t1, t2, t3])
    peaks_s = starts_s + t_peak
    starts_idx = np.round(starts_s / Tclk).astype(int)
    peaks_idx = np.round(peaks_s / Tclk).astype(int)

    n_clip_hi = int(np.sum(noisy_f > ADC_MAX))
    n_clip_lo = int(np.sum(noisy_f < 0.0))

    # seam check: deterministic signal above baseline at the two window edges
    head_lsb = float(train[0])          
    tail_lsb = float(train[-1])          
    seam_step_lsb = tail_lsb - head_lsb 
    base_code = int(np.round(baseline))
    edges_on_baseline = bool(clean[0] == base_code and clean[-1] == base_code)

    info = dict(
        t=t, clean=clean, noisy=noisy, clean_f=clean_f, noisy_f=noisy_f,
        Tclk=Tclk, fs=fs, n_samples=n, T_window=T_window,
        baseline_lsb=baseline, amps_lsb=amps, thr_lsb=thr,
        pulse_starts_s=starts_s, pulse_peaks_s=peaks_s,
        pulse_starts_idx=starts_idx, pulse_peaks_idx=peaks_idx,
        sep_s=sep, gap_s=gap, tail_s=tail, lead_s=lead,
        t_peak_s=t_peak, model=model,
        peak_code=int(noisy.max()), min_code=int(noisy.min()),
        n_clip_hi=n_clip_hi, n_clip_lo=n_clip_lo,
        head_lsb=head_lsb, tail_lsb=tail_lsb, seam_step_lsb=seam_step_lsb,
        edges_on_baseline=edges_on_baseline, baseline_code=base_code,
        wrap_tails=wrap_tails,
        rom_bits=n * ADC_BITS,
    )

    if verbose:
        print(f"--- periodic window -------------------------------------")
        print(f"  fs            : {fs/1e6:.3f} MS/s   (Tclk = {Tclk*1e9:.2f} ns)")
        print(f"  tau_rise      : {tau_rise_s*1e9:.1f} ns "
              f"({tau_rise_s/Tclk:.1f} clk)")
        print(f"  tau_decay     : {tau_decay_s*1e6:.2f} us "
              f"({tau_decay_s/Tclk:.0f} clk)")
        print(f"  model         : {model}, peak at +{t_peak/Tclk:.1f} clk from start")
        print(f"  depth         : {n} samples  = {T_window*1e6:.2f} us "
              f"= {n*ADC_BITS/1024:.1f} kbit of ROM")
        print(f"  baseline      : {baseline:.0f} LSB  ({baseline_pct:.2f} % FS)")
        print(f"  noise sigma   : {noise_sigma_lsb:.1f} LSB   "
              f"settle threshold: {thr:.1f} LSB")
        print(f"  amplitudes    : " +
              ", ".join(f"{a:.0f} LSB ({p:.1f} %)" for a, p in zip(amps, amp_pct)))
        print(f"  P1 start/peak : idx {starts_idx[0]} / {peaks_idx[0]}")
        print(f"  P2 start/peak : idx {starts_idx[1]} / {peaks_idx[1]}   "
              f"(gap = {gap/tau_decay_s:.2f} tau_d)")
        print(f"  P3 start/peak : idx {starts_idx[2]} / {peaks_idx[2]}   "
              f"(sep = {sep/tau_decay_s:.2f} tau_d = {sep/Tclk:.0f} clk)")
        print(f"  code range    : {info['min_code']} .. {info['peak_code']} "
              f"(ADC_MAX = {ADC_MAX})")
        print(f"  seam          : first={clean[0]} last={clean[-1]} "
              f"(baseline code {base_code}); residual tail at end = "
              f"{tail_lsb:.3f} LSB")
        if not edges_on_baseline:
            print(f"  ** WARNING: window does not start AND end on the "
                  f"baseline code -- increase tail_taus / lead_taus, or lower "
                  f"settle_thresh_lsb")
        if n_clip_hi:
            print(f"  ** WARNING: {n_clip_hi} samples clip at full scale -- "
                  f"lower amp_pct or baseline_pct")
        if n_clip_lo:
            print(f"  ** WARNING: {n_clip_lo} samples clip at 0 -- "
                  f"raise baseline_pct (aim for baseline > 4*sigma "
                  f"= {4*noise_sigma_lsb:.0f} LSB)")
        print(f"---------------------------------------------------------")

    return info


# ----------------------------------------------------------------------
# Exporters
# ----------------------------------------------------------------------
def write_vhdl_pkg(samples, path="pulse_rom_pkg.vhd",
                   pkg_name="pulse_rom_pkg", rom_name="PULSE_ROM",
                   adc_bits=ADC_BITS, per_line=10, header=""):
    """Write the samples as a VHDL package holding an integer array.

    Integers (not hex) because 14 bits is not a multiple of 4, so plain hex
    literals do not map onto std_logic_vector(13 downto 0) in VHDL-93.
    Convert on read:  std_logic_vector(to_unsigned(PULSE_ROM(addr), ADC_WIDTH))
    """
    samples = np.asarray(samples, dtype=np.int64)
    depth = samples.size
    lines = []
    lines.append("-- Automatically generated by periodic_pulse_window.py.")
    lines.append("-- Do not edit by hand.")
    for h in header.splitlines():
        lines.append(f"-- {h}")
    lines.append("")
    lines.append("library ieee;")
    lines.append("use ieee.std_logic_1164.all;")
    lines.append("use ieee.numeric_std.all;")
    lines.append("")
    lines.append(f"package {pkg_name} is")
    lines.append("")
    lines.append(f"  constant ADC_WIDTH : natural := {adc_bits};")
    lines.append(f"  constant ROM_DEPTH : natural := {depth};")
    lines.append("")
    lines.append("  type pulse_rom_t is array (0 to ROM_DEPTH-1) of "
                 "integer range 0 to 2**ADC_WIDTH-1;")
    lines.append("")
    lines.append(f"  constant {rom_name} : pulse_rom_t := (")

    body = []
    for i in range(0, depth, per_line):
        chunk = ", ".join(f"{v:5d}" for v in samples[i:i + per_line])
        body.append(f"    {chunk}")
    lines.append(",\n".join(body))
    lines.append("  );")
    lines.append("")
    lines.append(f"end package {pkg_name};")
    lines.append("")

    with open(path, "w") as f:
        f.write("\n".join(lines))
    return path


def write_sample_file(samples, path="pulse_window.txt", fmt="dec",
                      adc_bits=ADC_BITS):
    """One sample per line, for a TEXTIO-based loader (recommended for big depths).

    fmt = "dec" -> plain integers   (VHDL: read(l, v))
    fmt = "bin" -> 14-char binary   (VHDL: read(l, slv_var))
    fmt = "hex" -> 4-char hex, zero-extended to 16 bits (Verilog $readmemh)
    """
    samples = np.asarray(samples, dtype=np.int64)
    with open(path, "w") as f:
        for v in samples:
            if fmt == "dec":
                f.write(f"{v}\n")
            elif fmt == "bin":
                f.write(format(int(v), f"0{adc_bits}b") + "\n")
            elif fmt == "hex":
                f.write(format(int(v), "04X") + "\n")
            else:
                raise ValueError("fmt must be 'dec', 'bin' or 'hex'")
    return path


# ----------------------------------------------------------------------
# Plot
# ----------------------------------------------------------------------
def plot_window(info, n_periods=1, path=None, show=True):
    import matplotlib.pyplot as plt

    noisy = np.tile(info["noisy"], n_periods)
    clean = np.tile(info["clean"], n_periods)
    n = info["n_samples"]
    x = np.arange(noisy.size)

    fig, ax = plt.subplots(figsize=(13, 4.5))
    ax.plot(x, noisy, lw=0.6, color="0.55", label="noisy (to ADC/ROM)")
    ax.plot(x, clean, lw=1.2, color="C0", label="clean")
    ax.axhline(info["baseline_lsb"], color="C2", ls="--", lw=0.9, label="baseline")
    ax.axhline(ADC_MAX, color="C3", ls=":", lw=0.9, label="full scale")

    for k in range(n_periods):
        for i, idx in enumerate(info["pulse_peaks_idx"]):
            ax.axvline(k * n + idx, color="C1", ls=":", lw=0.8)
        if k:
            ax.axvline(k * n, color="k", ls="-", lw=1.0, alpha=0.5)

    ax.set_xlabel("sample index (ROM address)")
    ax.set_ylabel("ADC code [LSB]")
    ax.set_title(f"Periodic stimulus window - depth {n} samples "
                 f"({info['T_window']*1e6:.1f} us @ {info['fs']/1e6:.0f} MS/s)")
    ax.set_xlim(0, noisy.size)
    ax.legend(loc="upper right", fontsize=8)
    ax.grid(alpha=0.25)
    fig.tight_layout()

    if path:
        fig.savefig(path, dpi=130)
    if show:
        plt.show()
    return fig


# ----------------------------------------------------------------------
# Demo
# ----------------------------------------------------------------------
if __name__ == "__main__":

    # Run this script to generate the input pulses into a "vhdl" pkg:
    
    info = generate_periodic_test_window(
 
        # How fast the ADC samples. 125e6 = 125 million samples per
        fs=125e6,
 
        # How fast the pulse goes UP. Bigger = slower, rounder edge.
        # The rise measured (10% to 90%) is about 2.2x this.
        tau_rise_s=25e-8,
 
        # How fast the pulse comes back DOWN. Bigger tau_decay = much longer ROM.
        tau_decay_s=2e-5,
 
        # Height of each pulse as a percentage of full scale
        # (100% = 16383), in the order (P1, P2, P3).
        # Watch out: P2 and P3 overlap, keep sum under ~90%.
        amp_pct=(35.0, 35.0, 25.0),
 
        # The flat DC level the signal sits on when nothing is happening.
        # Keep it at least 4x the noise so the negative noise wiggles
        baseline_pct=10.0,
 
        # How noisy the signal is, in ADC codes..
        noise_sigma_lsb=50.0,
 
        # How close P3 comes after P2, counted in tau_decay.
        # SMALLER = worse pileup. 0.35 means P3 lands while P2 is still
        pileup_sep_taus=0.35,
 
        # Quiet baseline BEFORE the first pulse, in tau_decay.
        # samples to reset and lock its baseline. 0.6 = 1500 samples.
        lead_taus=1.9,
 
        # Distance from P1 to P2, in tau_decay. This is how long P1 gets
        # to decay before P2 shows up.
        gap_taus=4.0,
 
        # Quiet time AFTER the pileup, to the end of the window.
        #   5.0 -> 55 codes    7.0 -> 7 codes    10.0 -> 0.4 codes
        tail_taus=4.5,
 
        # Round the total length up to a multiple of this.
        depth_multiple=8,
 
        # Fixes the random noise.
        seed=0,
 
        # "tanh" = the shape model used.
        # "exp"  = (1-exp(-t/tau_r))*exp(-t/tau_d), strictly causal.
        model="tanh",
    )

    hdr = (f"depth={info['n_samples']}  fs={info['fs']/1e6:.1f}MS/s  "
           f"tau_r={info['t_peak_s']*1e9:.0f}ns_peak\n"
           f"pulse peaks at samples "
           f"{list(map(int, info['pulse_peaks_idx']))}")

    write_vhdl_pkg(info["noisy"], "pulse_rom_pkg.vhd", header=hdr)
    write_sample_file(info["noisy"], "pulse_window.txt", fmt="dec")
    plot_window(info, n_periods=1, path="pulse_window.png", show=False)
    print("wrote pulse_rom_pkg.vhd, pulse_window.txt, pulse_window.png")