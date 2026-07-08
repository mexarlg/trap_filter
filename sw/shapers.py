"""
Pulse shaper models and input generation (fixed-point).

Fixed-point width definitions and helpers, the input pulse generator, 
the Jordanov trapezoidal filter, the recursive moving average filter, 
and the pole-zero decay compensation helper.

"""

import numpy as np

# ----------------------------------------------------------------------
# Fixed-point parameters
# ----------------------------------------------------------------------
ADC_BITS   = 14                     # unsigned ADC resolution
ADC_MAX    = (1 << ADC_BITS) - 1    # Max ADC value -> 16383

# ----------------------------------------------------------------------
# Jordanov parameters
# ----------------------------------------------------------------------
M_FRAC     = 4                      # fractional bits of the M coefficient from Jordanov
D_BITS     = 18                     # signed width of d (delayed diff) from Jordanov
P_BITS     = 25                     # signed width of p (1st accumulator) from Jordanov
S_BITS     = 36                     # signed width of s (2nd accumulator) from Jordanov
D_SAT      = (1 << (D_BITS - 1)) - 1  # saturation limit for d before DSP from Jordanov

# ----------------------------------------------------------------------
# Moving average parameters
# ----------------------------------------------------------------------
MA_DIFF_BITS = 16     # v[n] - v[n-d] from moving average
MA_ACC_BITS  = 25     # accumulator, sized for d up to 1024 from moving average

# Checks if a value fits on a signed bit width
def _fits_signed(val, bits):
    """True if val fits in a signed 'bits' wide 2 complement register."""
    lo = -(1 << (bits - 1))
    hi = (1 << (bits - 1)) - 1
    return lo <= val <= hi

# From continuous to discrete
def quantize_adc(analog):
    """Quantize an analog waveform to unsigned 14-bit ADC codes (0 .. ADC_MAX)."""
    return np.clip(np.round(analog), 0, ADC_MAX).astype(np.int64)


# ----------------------------------------------------------------------
# Input pulse generation
# ----------------------------------------------------------------------
def generate_input(n_samples = 1048,
                   fs = 100e6,           # sampling rate [Hz]
                   t0_frac = 0.25,       # pulse start as timespan fraction
                   amplitude = 300.0,    # pulse amplitude
                   tau_rise_s = 8e-8,    # rise time constant [s]
                   tau_decay_s = 2e-5,   # preamp decay time constant [s]
                   noise_offset = 1,     # offset of baseline due noise (P0)
                   noise_sigma = 30,     # white noise std dev
                   seed = 0):            # seed for noise randomness
    """Return (t, clean, noisy) arrays of the pulse signal (14 bits).
    """

    # timespan
    Tclk = 1.0 / fs
    t = np.arange(n_samples) * Tclk
    t0 = t0_frac * n_samples * Tclk
    dt = t - t0
    
    # rising contribution: tanh ((t - t0) / tau) + 1
    rising = 1.0 + np.tanh(dt / tau_rise_s)
    
    # tail decay contribution: exp((t - t0) / tau_decay)
    decay = np.exp(- dt / tau_decay_s)

    # clean pulse (amplitude divided since rising goes 0 -> 2)
    clean = 0.5 * amplitude * rising * decay

    # noisy pulse
    rng = np.random.default_rng(seed)
    noisy = clean + noise_offset + rng.normal(0.0, noise_sigma, n_samples)

    # discretize to 14 bit unsigned ADC
    clean = quantize_adc(clean)
    noisy = quantize_adc(noisy)

    return t, clean, noisy, Tclk


# ----------------------------------------------------------------------
# Recursive Jordanov trapezoidal
# ----------------------------------------------------------------------
def jordanov_trapezoidal(v, k, m, M, out_shift=None, check_overflow=False):
    """
    Recursive Jordanov trapezoidal filter (signed, fixed-point).
    Storage is unsigned 14-bit and the pipeline is signed 2-complement.
    M is quantized to a scaled integer and applied as (M_scaled * d) >> M_FRAC. 

    Parameters
    ----------
    v : ndarray   input samples (unsigned 14-bit ADC)
    k : int       ramp length (in samples)
    m : int       flat top width (in samples) (l = k + m)
    M : float     decay compensation factor
                  M = 1/(exp(Tclk/tau_decay)-1); (can be approx).
    out_shift : int or None   final right-shift for output scaling
    check_overflow : bool      raise if any register exceeds its planned width

    Returns
    -------
    s : ndarray   shaped output (int)
    """

    # Precheck and preallocation
    k = int(k)
    m = int(m)
    l = k + m
    N = len(v)
    s = np.zeros(N, dtype=np.int64)

    # Quantize M to a scaled integer coefficient
    M_scaled = int(round(M * (1 << M_FRAC)))
    rnd_m = 1 << (M_FRAC - 1)

    # input as exact integers (unsigned storage, sign in math)
    v = v.astype(np.int64)

    # State registers
    p_prev = 0     # accumulator p[n-1]
    s_prev = 0     # accumulator s[n-1]

    # Delay lines as circular buffers of 14 unsigned bits (x2 DP BRAM)
    for n in range(N):

        # PIPELINE STAGES:

        # input signal and delays (14 bit unsigned from adc, 15 bit signed for pipeline)
        vn = int(v[n])
        v_k = int(v[n - k]) if n - k >= 0 else 0
        v_l = int(v[n - l]) if n - l >= 0 else 0
        v_kl = int(v[n - k - l]) if n - k - l >= 0 else 0

        # delayed difference (4 additions -> 2 extra bits -> N bits = 14 mag bits + 2 extra bits + 1 sign bit + 1 guard bit = 18 bits = d)
        d = vn - v_k - v_l + v_kl               # d^{k,l}

        # saturate d (if overflow, make sure it doesnt wrap, but rather keep its maximum value)
        d = max(-D_SAT - 1, min(D_SAT, d))      # make sure d stays on 18 bits

        # first accumulator over k (log2(k <= 256) = 8 bits -> N bits (p) = 14 mag bits + 8 bits + 1 bit sign + 2 guard bits = 25 bits = p)
        p = p_prev + d                          # first accumulator

        # Multiplication (M = 12 mag bits + 4 fraction bits + 1 sign bit = 17 bits) (d = 18 bits) -> (Md = 17 + 18 = 35 = Md) 
        Md_full = M_scaled * d                  # DSP product

        # M scaled back (from 35 bits minus the fraction bits) -> (Md = 35 bits - 4 bits = 31 bits = Md)
        Md = (Md_full + (rnd_m if Md_full >= 0 else -rnd_m)) >> M_FRAC

        # addition (p = 25 bits) + (M = 31 bits) -> (N bits of r = 31 + 1 = 32 bits = r)
        r = p + Md                              # pole zero corrected

        # Second accumulator over k = 128 bits -> log2(k) = 8 (if 128 < k < 256) -> (32 bits + 8 bits = 40 bits = s) or (s = 36 if assumming M domination)
        s[n] = s_prev + r                       # final accumulator (output)

        # optional overflow check for accumulators (p, s)
        if check_overflow:
            if not _fits_signed(p, P_BITS):
                raise OverflowError(f"p overflow at n={n}: {p} exceeds {P_BITS}b")
            if not _fits_signed(int(s[n]), S_BITS):
                raise OverflowError(f"s overflow at n={n}: {s[n]} exceeds {S_BITS}b")

        # update next iteration
        p_prev = p
        s_prev = s[n]

    # final output rescale view to 15 bits signed (iteration over)
    if out_shift is not None and out_shift > 0:
        rnd_o = 1 << (out_shift - 1)
        s = np.where(s >= 0, (s + rnd_o) >> out_shift, -((-s + rnd_o) >> out_shift))

    return s

# ----------------------------------------------------------------------
# Recursive Moving Average
# ----------------------------------------------------------------------
# Fixed-point widths (14b unsign ADC or 15 bit signed shaper as inputs):
#   diff = v[n] - v[n-d]  : 14 + log2(2) + 1 (sign) = 16 bits signed
#   acc  = acc + diff     : 14 + log2(d) + sign  (= 25 bits)
#   output = acc >> log2(d) : normalization (/d)

def moving_average(v, d, out_shift=None, check_overflow=False, signed_input=False):
    """
    Recursive moving average, fixed-point. Handles both input 15b sign / 14b unsign
        - signed_input=False : unsigned 14-bit ADC
        - signed_input=True  : signed  15-bit ADC

    Equations:
        acc[n] = acc[n-1] + v[n] - v[n-d]     (running sum)
        y[n]   = acc[n] >> log2(d)            (/d normalization at output)

    Parameters
    ----------
    v : ndarray   input samples (unsigned 14b codes, or signed 15b codes)
    d : int       window length in samples (use a power of two for a clean >>)
    out_shift : int or None   final right-shift; if None, uses log2(d)
    check_overflow : bool      raise if any register exceeds its planned width
    signed_input : bool        False = unsigned 14b ADC, True = signed 15b ADC

    Returns
    -------
    s : ndarray   averaged output (int)
    """

    # Precheck and preallocation
    d = int(d)
    N = len(v)
    s = np.zeros(N, dtype=np.int64)

    # input as exact integers
    v = v.astype(np.int64)

    # State registers
    acc_prev = 0     # single accumulator acc[n-1]

    # Delay line as circular buffer (single DP BRAM: 1 rd + 1 wr)
    for n in range(N):

        # PIPELINE STAGES:

        # input signal and delay (unsigned -> zero-extend, signed -> as-is)
        vn = int(v[n])
        v_d = int(v[n - d]) if n - d >= 0 else 0

        # delayed difference (2 terms -> +1 bit; +1 sign -> 16 bits signed)
        diff = vn - v_d

        # single accumulator: running sum of diff (14 + log2(d) bits)
        acc = acc_prev + diff
        s[n] = acc

        # optional overflow check (diff, acc)
        if check_overflow:
            if not _fits_signed(diff, MA_DIFF_BITS):
                raise OverflowError(f"diff overflow at n={n}: {diff} exceeds {MA_DIFF_BITS}b")
            if not _fits_signed(int(acc), MA_ACC_BITS):
                raise OverflowError(f"acc overflow at n={n}: {acc} exceeds {MA_ACC_BITS}b")

        # update next iteration
        acc_prev = acc

    # Truncation to match VHDL shift_right
    if out_shift is None:
        out_shift = int(round(np.log2(d)))
    if out_shift > 0:
        s = s >> out_shift
    return s

# Computes ideal compensation factor for Jordanov, for a given decay constant
def M_from_tau(tau_decay_s=2e-6, Tclk = 1.0/125e6):
    """Pole zero decay compensation factor for a given decay constant."""
    return 1.0 / (np.exp(Tclk / tau_decay_s) - 1.0)
