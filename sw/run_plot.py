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
    The input signal is quantized to a 14 bit unsigned ADC and the filter runs in the
    same integer widths. Datapath is signed 2-complement and storage is unsigned.

    Target widths (14b unsigned ADC, 18x18 DSP, k around 128, m around 84, M_frac=4):
        delay word : 14b unsigned     d          : 18b signed
        p          : 25b signed       M coeff    : 17b signed
        M*d prod   : 35b signed       M*d scaled : 31b signed 
        r          : 32b signed       s          : 36b signed

Run:  python run_plot.py
"""

import matplotlib.pyplot as plt

from shapers import *
from plot_helpers import *

def main():

    # ------------------------------------------------------------------------
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
    # Sampling parameters
    # ------------------------------------------------------------------------
    n_samples = 1024                # number of samples at fs
    fs = 125e6                      # sample freq [hz]
    Tclk = 1.0 / fs                 # sample period [8 ns for 125 Mhz]

    # ------------------------------------------------------------------------
    # Input signal parameters
    # ------------------------------------------------------------------------
    amplitude = int(0.6*ADC_MAX)    # pulse amplitude as percentage of ADC max value
    tau_decay_s = 2e-5              # nominal decay time constant [s]
    tau_r_min_s = 5e-8              # min nominal rise time constant for high energy (50 ns) [s]
    tau_r_max_s = 25e-8             # max nominal rise time constant for high energy (250 ns) [s]
    tau_rise_s = tau_r_max_s        # selected rise time for simulation [s]
    noise_offset = int(0.1*amplitude)    # offset of baseline
    noise_sigma = int(0.1*amplitude)     # white noise std dev

    # ------------------------------------------------------------------------
    # Jordanov parameters in n samples (k, m, M)
    # ------------------------------------------------------------------------
    k0, m0 = 105, 84
    M0 = M_from_tau(tau_decay_s, Tclk)  # ideal M
    M0 = 2496.61                        # similar M to allow k*M as power of 2 for easy shift
    out_shift0 = 18 # Gain is selected as k*M -> k and M have to be power of 2 as to allow shifting -> with these params -> shift 18 bits from a 36b output
    
    # ------------------------------------------------------------------------
    # Moving average parameters in n samples
    # ------------------------------------------------------------------------
    delay = 8                 # delay of moving average (Number of points, must be power of 2^n)
    shifter = 3                 # shift required for (1/N division), delay must be multiple of 2^n

    # ------------------------------------------------------------------------
    # Filter selection
    # ------------------------------------------------------------------------
    SHAPER_SELECT = 0               # chooses shaper algorithm, 1 for Jordanov, 0 for moving average

    # ------------------------------------------------------------------------
    # Analysis
    # ------------------------------------------------------------------------

    # k is limited by slower rise time, for this case a k = 128 seems conservative enough for noise levels of 30%
    # m is also limited by the slower rise time, usually shorter than k, expected to allow good moving avg, ex: k = 82
    # both parameter selections for fast rise time have a very good response, slow rise time is the edge case

    # regarding for pulse trigger (fast jordanov), at noise levels of 10%, a fast pulse could be achieved at 50% of rising edge, at the edge case of a slow pulse.
    # the threshold value should not be the amplitude of the pulse, but rather a % of it, lower could be affected by levels of noise
    # some values: k = 14, m = 10 (acieves good pulse diffrerentiation between noise, with a thereshold of 30% of amplitude, at 50% of rising edge)

    # ------------------------------------------------------------------------
    # Workspace
    # ------------------------------------------------------------------------

    # input generation kwargs, reused when the noise slider regenerates the pulse
    gen_kwargs = dict(n_samples=n_samples, fs=fs, amplitude=amplitude,
                      tau_rise_s=tau_rise_s, tau_decay_s=tau_decay_s,
                      noise_offset=noise_offset, noise_sigma=noise_sigma)

    t, clean, noisy, Tclk = generate_input(**gen_kwargs)
    t_us = t * 1e6  # time in microseconds

    # ------------------------------------------------------------------------
    # Plot of clean and noisy input signal v[n]
    # ------------------------------------------------------------------------

    # Plot axis
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
    setup_axes(ax_in, x_major=1.0, x_minor=2)

    # ------------------------------------------------------------------------
    # Plot and computation of output y[n]
    # ------------------------------------------------------------------------

    # select shaper (initial curve):
    if SHAPER_SELECT == 1:
        y0 = jordanov_trapezoidal(noisy, k0, m0, M0, out_shift=out_shift0)
    else:
        y0 = moving_average(noisy, delay, out_shift=shifter, signed_input= False)

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
        rf'Fixed-Point Shaper Output ($k={k0}$, $m={m0}$, $M={M0:.1f}$)'
    )
    ax_out.set_ylim(y_min, y_max)  

    # Output axes ticks and grid
    setup_axes(ax_out, x_major=1.0, x_minor=0.5)

    # shared mutable input state so the noise slider can regenerate the pulse
    state = {'noisy': noisy}

    # ------------------------------------------------------------------------
    # Build the slider UI
    # ------------------------------------------------------------------------
    if SHAPER_SELECT == 1:
        widgets = build_jordanov(fig, ax_in, ax_out, t_us, line_out, state,
                                 gen_kwargs, y_min, y_max,
                                 k0, m0, M0, out_shift0, tau_decay_s, Tclk)
    else:
        widgets = build_moving_average(fig, ax_in, ax_out, t_us, line_out, state,
                                       gen_kwargs, y_min, y_max, delay)

    plt.show()


if __name__ == '__main__':
    main()
