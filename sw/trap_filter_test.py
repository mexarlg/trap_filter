"""
Jordanov Trapezoidal FIR Filter - Pretest for FPGA development

Author: Aldo Lupio

Reference:
    V.T. Jordanov, G.F. Knoll, "Digital synthesis of pulse shapes in real time
    for high resolution radiation spectroscopy", NIM A 345 (1994) 337-345.

Input signal:
    A detector preamplifier pulse with finite rise time and exponential decay with white noise
        v(t) = A0 * (1 + tanh((t - t0)/tau_rise)) * exp(-(t - t0)/tau_decay) + P0 + white noise

Filter design:

    Given input v[n]:
        d^{k,l}[n] = v[n] - v[n-k] - v[n-l] + v[n-k-l] (double delay-diff)
        p[n]       = p[n-1] + d^{k,l}[n]               (accumulator)
        r[n]       = p[n]   + M * d^{k,l}[n]           (pole-zero deconv term)
        s[n]       = s[n-1] + r[n]                     (final accumulator = output)

    Jordanov parameters:
        k  = rise time of trapezoid (samples)    -> ramp length
        m  = flat top length (l = k + m)         -> so l-k = m
        M  = decay time compensation (pole-zero) ->  M = 1/(exp(Tclk/tau_decay)-1)

FPGA fixed point model:
    The input signal is quantized to a 14-bit unsigned ADC and the filter runs in the
    same integer widths. Datapath is signed 2-complement and storage is unsigned.

    Target widths (14b unsigned ADC, 18x18 DSP, k around 128, m around 84, M_frac=4):
        delay word : 14b unsigned     d          : 18b signed
        p          : 25b signed       M coeff    : 17b signed
        M*d prod   : 35b signed       M*d scaled : 31b signed 
        r          : 32b signed       s          : 36b signed
"""

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.widgets import Slider, Button
from matplotlib.ticker import MultipleLocator, AutoMinorLocator

# ----------------------------------------------------------------------
# Fixed-point parameters
# ----------------------------------------------------------------------
ADC_BITS   = 14                     # unsigned ADC resolution
ADC_MAX    = (1 << ADC_BITS) - 1    # Max ADC value -> 16383
M_FRAC     = 4                      # fractional bits of the M coefficient
D_BITS     = 18                     # signed width of d (delayed diff)
P_BITS     = 25                     # signed width of p (1st accumulator)
S_BITS     = 36                     # signed width of s (2nd accumulator)
D_SAT      = (1 << (D_BITS - 1)) - 1  # saturation limit for d before DSP


def _fits_signed(val, bits):
    """True if val fits in a signed 'bits' wide 2 complement register."""
    lo = -(1 << (bits - 1))
    hi = (1 << (bits - 1)) - 1
    return lo <= val <= hi


def quantize_adc(analog):
    """Quantize an analog waveform to unsigned 14-bit ADC codes (0 .. ADC_MAX)."""
    return np.clip(np.round(analog), 0, ADC_MAX).astype(np.int64)


# ----------------------------------------------------------------------
# Input pulse generation
# ----------------------------------------------------------------------
def generate_input(n_samples = 1048,
                   fs = 100e6,           # sampling rate [Hz]
                   t0_frac = 0.15,       # pulse start as timespan fraction
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


def M_from_tau(tau_decay_s=2e-6, Tclk = 1.0/125e6):
    """Pole zero decay compensation factor for a given decay constant."""
    return 1.0 / (np.exp(Tclk / tau_decay_s) - 1.0)


def main():
    
    # Expected parameter ranges:
    # ------------------------------------------------------------------------
    # tau_decay -> dependant of preAmp, around 2e-5 [s] (20000 ns = 0.2 microseconds) (can vary between high/low energy due noise/temp etc)
    # tau_rise -> fast time rise of 5e-8 (50 ns) and maximum time rise of 25e-8 (250 ns) (nominal 8e-8) [s]
    # noise_sigma -> less than 5% of amplitude for nominal high energy (much higher for lower energy)
    # amplitude -> around 700 for nominal high energy
    # sampling rate -> around 125 Mhz (8 ns per sample)

    # M dependent of preAmp (usually known, fixed by hw)
    # k, m can be configurable (simpler if fixed, multiples of 2 to allow easy division) (usually m > k, even doubled)
    # ------------------------------------------------------------------------


    # Configurable parameters to generate input signal with noise
    # ------------------------------------------------------------------------
    n_samples = 1024                # number of samples at fs
    fs = 125e6                      # sample freq [hz]
    Tclk = 1.0 / fs                 # sample period [8 ns for 125 Mhz]
    amplitude = int(0.6*ADC_MAX)    # pulse amplitude as percentage of ADC max value
    tau_decay_s = 2e-5              # nominal decay time constant [s]
    tau_r_min_s = 5e-8              # min nominal rise time constant for high energy (50 ns) [s]
    tau_r_max_s = 25e-8             # max nominal rise time constant for high energy (250 ns) [s]
    tau_rise_s = tau_r_max_s        # selected rise time for simulation [s]
    noise_offset = int(0.1*amplitude)    # offset of baseline
    noise_sigma = int(0.1*amplitude)     # white noise std dev
    # ------------------------------------------------------------------------
    # Jordanov parameters in n samples (k, m, M)
    k0, m0 = 105, 84
    M0 = M_from_tau(tau_decay_s, Tclk)  # ideal M
    M0 = 2496.61                        # similar M to allow k*M as power of 2 for easy shift
    out_shift0 = 18 # Gain is selected as k*M -> k and M have to be power of 2 as to allow shifting -> with these params -> shift 18 bits from a 36b output
    # ------------------------------------------------------------------------

    # Jordanov parameters analysis:
    # k is limited by slower rise time, for this case a k = 128 seems conservative enough for noise levels of 30%
    # m is also limited by the slower rise time, usually shorter than k, expected to allow good moving avg, ex: k = 82
    # both parameter selections for fast rise time have a very good response, slow rise time is the edge case

    # regarding for pulse trigger (fast jordanov), at noise levels of 10%, a fast pulse could be achieved at 50% of rising edge, at the edge case of a slow pulse.
    # the threshold value should not be the amplitude of the pulse, but rather a % of it, lower could be affected by levels of noise
    # some values: k = 14, m = 10 (acieves good pulse diffrerentiation between noise, with a thereshold of 30% of amplitude, at 50% of rising edge)

    t, clean, noisy, Tclk = generate_input(n_samples=n_samples, fs=fs, amplitude=amplitude, tau_rise_s=tau_rise_s, tau_decay_s=tau_decay_s,
                                        noise_offset=noise_offset, noise_sigma=noise_sigma)
    t_us = t * 1e6  # time in microseconds

    # ------------------------------------------------------------------------
    # Plot of clean and noisy input signal v[n]
    # ------------------------------------------------------------------------

    # Plot axis (reality input is 14b unsigned, output 15 bit signed) -> Allow only discretized input pulse + its noise as top limit
    y_min = 0 
    y_max = amplitude + noise_offset + noise_sigma

    fig, (ax_in, ax_out) = plt.subplots(2, 1, figsize=(11, 8), sharex=True)
    plt.subplots_adjust(left=0.1, bottom=0.32, hspace=0.25)
    ax_in.plot(t_us, noisy, lw=0.7, color='0.6', marker = '.',markersize=3, label='Noisy pulse')
    ax_in.plot(t_us, clean, lw=1.2, color='tab:blue', marker = '.', markersize=3, label='Clean pulse')
    ax_in.set_ylabel('Pulse Amplitude [14b usign]')
    ax_in.set_title(
        rf'Input Pulse '
        rf'($ADC={ADC_BITS}$ bits, '
        rf'$f_s={fs/(1e6):.0f}$ MHz, '
        rf'$n={n_samples}$, '
        rf'$A_0={amplitude}$, '
        rf'$\tau_c={tau_decay_s}$ s, '
        rf'$\tau_r={tau_rise_s}$ s, '
        rf'$\sigma_n={noise_sigma}$)'
    )
    ax_in.legend(loc='upper right')
    ax_in.set_ylim(y_min, y_max)          # fixed y-axis (shared scale with output)

    # Input axes ticks and grid
    ax_in.xaxis.set_major_locator(MultipleLocator(1.0))   
    ax_in.xaxis.set_minor_locator(MultipleLocator(2))   
    ax_in.yaxis.set_minor_locator(AutoMinorLocator(2))
    ax_in.tick_params(axis='x', which='major', length=6)
    ax_in.tick_params(axis='x', which='minor', length=3)
    ax_in.grid(which='major', linewidth=1.0, alpha=0.35)
    ax_in.grid(which='minor', linewidth=0.5, alpha=0.15)

    # ------------------------------------------------------------------------
    # Plot and computation of output y[n]
    # ------------------------------------------------------------------------

    y0 = jordanov_trapezoidal(noisy, k0, m0, M0, out_shift=out_shift0)
    (line_out,) = ax_out.plot(
        t_us, y0,
        lw=1.0,
        color='tab:red',
        marker='.',
        markersize=3,
        markerfacecolor='k',
        markeredgecolor='k'
    )
    ax_out.set_xlabel('Time [µs]')
    ax_out.set_ylabel('Shaper Output [15b sign]')
    ax_out.set_title(
        rf'Fixed-Point Jordanov Output ($k={k0}$, $m={m0}$, $M={M0:.1f}$)'
    )
    ax_out.set_ylim(y_min, y_max)         # fixed y-axis (same scale as input)

    # Grid
    ax_out.xaxis.set_major_locator(MultipleLocator(1.0))
    ax_out.xaxis.set_minor_locator(MultipleLocator(0.5))
    ax_out.yaxis.set_minor_locator(AutoMinorLocator(2))
    ax_out.tick_params(axis='x', which='major', length=6)
    ax_out.tick_params(axis='x', which='minor', length=3)
    ax_out.grid(which='major', linewidth=1.0, alpha=0.35)
    ax_out.grid(which='minor', linewidth=0.5, alpha=0.15)

    # style of sliders of graph to play around
    axcolor = '0.92'
    ax_k = plt.axes([0.12, 0.20, 0.7, 0.03], facecolor=axcolor)
    ax_m = plt.axes([0.12, 0.15, 0.7, 0.03], facecolor=axcolor)
    ax_M = plt.axes([0.12, 0.10, 0.7, 0.03], facecolor=axcolor)
    ax_ns = plt.axes([0.12, 0.05, 0.7, 0.03], facecolor=axcolor)

    # value of sliders of graph to play around
    # ------------------------------------------------------------------------
    s_k = Slider(ax_k, 'k (ramp)',      2, 400, valinit=k0, valstep=2)
    s_m = Slider(ax_m, 'm (flat top)',  0, 400, valinit=m0, valstep=2)
    s_M = Slider(ax_M, 'M (pole-zero)', 1, 8000, valinit=M0)
    s_ns = Slider(ax_ns, 'noise sigma', 0.0, amplitude/2, valinit=noise_sigma, valstep=5.0)

    # button for ideal compensation factor
    ax_pz = plt.axes([0.85, 0.10, 0.12, 0.05])
    btn_pz = Button(ax_pz, 'M = ideal')

    state = {'noisy': noisy}

    # helper function to recompute jordanov
    def recompute(_=None):
        # update jordanov params from slider
        k = int(s_k.val)
        m = int(s_m.val)
        M = s_M.val

        # recompute jordanov output
        y = jordanov_trapezoidal(state['noisy'], k, m, M, out_shift=out_shift0)

        # update graph
        line_out.set_ydata(y)
        ax_out.set_title(f'Fixed-Point Jordanov output  (k={k}, m={m}, M={M:.1f})')
        ax_out.set_ylim(y_min, y_max)
        fig.canvas.draw_idle()

    # helper function to recompute noise of input pulse
    def regen_noise(_=None):
        # recompute input with new noise
        _, cln, nsy, _ = generate_input(n_samples=n_samples, fs=fs, amplitude=amplitude, tau_rise_s=tau_rise_s, tau_decay_s=tau_decay_s,
                                        noise_sigma=s_ns.val)
        
        # new noise input, recompute output
        state['noisy'] = nsy
        ax_in.lines[0].set_ydata(nsy)
        recompute()

    # helper function to recompute compensation constant
    def set_ideal_M(_=None):
        s_M.set_val(M_from_tau(tau_decay_s, Tclk))

    # Update graph if sliders are changed
    s_k.on_changed(recompute)
    s_m.on_changed(recompute)
    s_M.on_changed(recompute)
    s_ns.on_changed(regen_noise)
    btn_pz.on_clicked(set_ideal_M)

    plt.show()


if __name__ == '__main__':
    main()