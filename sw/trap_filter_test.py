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
"""

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.widgets import Slider, Button


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
    """Return (t, clean, noisy) arrays of pulse signal."""

    # timespan
    Tclk = 1.0 / fs
    t = np.arange(n_samples) * Tclk
    t0 = t0_frac * n_samples * Tclk
    dt = t - t0
    
    # rising contribution: tanh ((t - t0) / tau) + 1
    rising = 1.0 + np.tanh(dt / tau_rise_s)
    
    # tail decay contribution: exp((t - t0) / tau_decay)
    decay = np.exp(- dt / tau_decay_s)

    # clean pulse
    clean = amplitude * rising * decay

    # noisy pulse
    rng = np.random.default_rng(seed)
    noisy = clean + noise_offset + rng.normal(0.0, noise_sigma, n_samples)

    return t, clean, noisy, Tclk


# ----------------------------------------------------------------------
# Recursive Jordanov trapezoidal
# ----------------------------------------------------------------------
def jordanov_trapezoidal(v, k, m, M):
    """
    Recursive Jordanov trapezoidal filter.

    Parameters
    ----------
    v : ndarray   input samples
    k : int       ramp length (in samples)
    m : int       flat top width (in samples) (l = k + m)
    M : float     decay compensation factor
                  M = 1/(exp(Tclk/tau_decay)-1); (can be approx).

    Returns
    -------
    s : ndarray   shaped output
    """

    # Precheck and preallocation
    k = int(k)
    m = int(m)
    l = k + m
    N = len(v)
    s = np.zeros(N)

    # State registers
    p_prev = 0.0     # accumulator p[n-1]
    s_prev = 0.0     # accumulator s[n-1]

    # Delay lines as circular buffers
    for n in range(N):

        # input signal and delays
        vn = v[n]
        v_k = v[n - k] if n - k >= 0 else 0.0
        v_l = v[n - l] if n - l >= 0 else 0.0
        v_kl = v[n - k - l] if n - k - l >= 0 else 0.0

        # accumulator, pole zero, output (normalization)
        d = (vn - v_k - v_l + v_kl)/(k) # double delayed difference d^{k,l}
        p = p_prev + d                  # first accumulator
        r = (p + M * d)/M               # pole zero corrected
        #r = p + M * d                  # pole zero corrected
        s[n] = s_prev + r               # final accumulator (output)

        # update next iteration
        p_prev = p
        s_prev = s[n]

    return s


def M_from_tau(tau_decay_s=2e-6, Tclk = 1.0/125e6):
    """Pole zero decay compensation factor for a given decay constant."""
    return 1.0 / (np.exp(Tclk / tau_decay_s) - 1.0)


def main():
    
    # Expected parameter ranges:
    # tau_decay -> dependant of preAmp, around 2e-5 [s] (20000 ns = 0.2 microseconds) (can vary between high/low energy due noise/temp etc)
    # tau_rise -> fast time rise of 5e-8 (50 ns) and maximum time rise of 25e-8 (250 ns) (nominal 8e-8) [s]
    # noise_sigma -> less than 5% of amplitude for nominal high energy (much higher for lower energy)
    # amplitude -> around 700 for nominal high energy
    # sampling rate -> around 125 Mhz (8 ns per sample)

    # M dependent of preAmp (usually known, fixed by hw)
    # k, m can be configurable (simpler if fixed, multiples of 2 to allow easy division) (usually m > k, even doubled)

    # Parameters to generate input signal with noise
    fs = 125e6 # sample freq [hz]
    amplitude = 350 # pulse amplitude
    tau_decay_s = 2e-5 # nominal decay time constant [s]
    tau_rise_s = 8e-8  # nominal rise time constant for high energy [s]
    tau_rise_s = 25e-8 # max nominal rise time constant for high energy [s]
    noise_offset = 0 # offset of baseline
    noise_sigma = 50 # white noise std dev
    t, clean, noisy, Tclk = generate_input(fs=fs, amplitude=amplitude, tau_rise_s=tau_rise_s, tau_decay_s=tau_decay_s,
                                        noise_offset=noise_offset, noise_sigma=noise_sigma)
    t_us = t * 1e6  # time in microseconds

    # Jordanov parameters in n samples (k, m, M)
    k0, m0 = 100, 50
    M0 = M_from_tau(tau_decay_s, Tclk)

    # Plot of clean and noisy input signal v[n]
    fig, (ax_in, ax_out) = plt.subplots(2, 1, figsize=(11, 8), sharex=True)
    plt.subplots_adjust(left=0.1, bottom=0.32, hspace=0.25)
    ax_in.plot(t_us, noisy, lw=0.7, color='0.6', label='noisy pulse')
    ax_in.plot(t_us, clean, lw=1.2, color='tab:blue', label='clean pulse')
    ax_in.set_ylabel('Pulse Amplitude []')
    ax_in.set_title('Input Pulse')
    ax_in.legend(loc='upper right')
    ax_in.grid(alpha=0.3)

    # Plot and computation of output y[n] (trapezoid)
    y0 = jordanov_trapezoidal(noisy, k0, m0, M0)
    (line_out,) = ax_out.plot(t_us, y0, lw=1.0, color='tab:red',
                          marker='.', markersize=3, markerfacecolor='k',
                          markeredgecolor='k', linestyle='-') 
    ax_out.set_xlabel('Time [us]')
    ax_out.set_ylabel('Shaper output []')
    ax_out.set_title(f'Jordanov trapezoidal output  (k={k0}, m={m0}, M={M0:.1f})')
    ax_out.grid(alpha=0.3)

    # style of sliders of graph to play around
    axcolor = '0.92'
    ax_k = plt.axes([0.12, 0.20, 0.7, 0.03], facecolor=axcolor)
    ax_m = plt.axes([0.12, 0.15, 0.7, 0.03], facecolor=axcolor)
    ax_M = plt.axes([0.12, 0.10, 0.7, 0.03], facecolor=axcolor)
    ax_ns = plt.axes([0.12, 0.05, 0.7, 0.03], facecolor=axcolor)

    # value of sliders of graph to play around
    s_k = Slider(ax_k, 'k (ramp)',      2, 400, valinit=k0, valstep=1)
    s_m = Slider(ax_m, 'm (flat top)',  0, 400, valinit=m0, valstep=1)
    s_M = Slider(ax_M, 'M (pole-zero)', 1, 8000, valinit=M0)
    s_ns = Slider(ax_ns, 'noise sigma', 0.0, 50.0, valinit=0.01)

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
        y = jordanov_trapezoidal(state['noisy'], k, m, M)

        # update graph
        line_out.set_ydata(y)
        ax_out.set_title(f'Jordanov trapezoidal output  (k={k}, m={m}, M={M:.1f})')
        ax_out.relim(); ax_out.autoscale_view(scaley=True)
        fig.canvas.draw_idle()

    # helper function to recompute noise of input pulse
    def regen_noise(_=None):
        # recompute input with new noise
        _, cln, nsy, _ = generate_input(fs=fs, tau_decay_s=tau_decay_s,
                                        noise_sigma=s_ns.val,
                                        seed=np.random.randint(1e6))
        
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
