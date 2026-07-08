"""
Plotting helpers for run_plot.

Holds the shared axis styling and the slider builders (Jordanov
and moving average).
"""

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.widgets import Slider, Button
from matplotlib.ticker import MultipleLocator, AutoMinorLocator

from shapers import *


# ----------------------------------------------------------------------
# Shared axis styling (grid, ticks)
# ----------------------------------------------------------------------
def setup_axes(ax, x_major, x_minor):
    """Apply the common tick + grid to an axis."""
    ax.xaxis.set_major_locator(MultipleLocator(x_major))
    ax.xaxis.set_minor_locator(MultipleLocator(x_minor))
    ax.yaxis.set_minor_locator(AutoMinorLocator(2))
    ax.tick_params(axis='x', which='major', length=6)
    ax.tick_params(axis='x', which='minor', length=3)
    ax.grid(which='major', linewidth=1.0, alpha=0.35)
    ax.grid(which='minor', linewidth=0.5, alpha=0.15)


# ----------------------------------------------------------------------
# Builder: Jordanov trapezoidal shaper UI
# ----------------------------------------------------------------------
def build_jordanov(fig, ax_in, ax_out, t_us, line_out, state,
                   gen_kwargs, y_min, y_max,
                   k0, m0, M0, out_shift0, tau_decay_s, Tclk):
    """Create the Jordanov sliders."""

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
    s_ns = Slider(ax_ns, 'noise sigma', 0.0, gen_kwargs['amplitude']/2,
                  valinit=gen_kwargs['noise_sigma'], valstep=5.0)

    # button for ideal compensation factor
    ax_pz = plt.axes([0.85, 0.10, 0.12, 0.05])
    btn_pz = Button(ax_pz, 'M = ideal')

    # helper function to recompute jordanov
    def recompute(_=None):
        # update jordanov params from slider
        k = int(s_k.val)
        m = int(s_m.val)
        M = s_M.val

        # current (possibly noise-regenerated) input
        nsy = state['noisy']

        # recompute shaper output with live slider values
        y0 = jordanov_trapezoidal(nsy, k, m, M, out_shift=out_shift0)

        # update graph
        line_out.set_ydata(y0)
        ax_out.set_title(f'Fixed-Point Shaper output  (k={k}, m={m}, M={M:.1f})')
        ax_out.set_ylim(y_min, y_max)
        fig.canvas.draw_idle()

    # helper function to recompute noise of input pulse
    def regen_noise(_=None):
        # recompute input with new noise
        kw = dict(gen_kwargs)
        kw['noise_sigma'] = s_ns.val
        _, cln, nsy, _ = generate_input(**kw)

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

    # keep slider
    return [s_k, s_m, s_M, s_ns, btn_pz]


# ----------------------------------------------------------------------
# Builder: Moving average shaper UI
# ----------------------------------------------------------------------
def build_moving_average(fig, ax_in, ax_out, t_us, line_out, state,
                         gen_kwargs, y_min, y_max, delay0):
    """Create the moving-average sliders and wire their recompute callback.
    """

    # style of sliders of graph to play around
    axcolor = '0.92'
    ax_d = plt.axes([0.12, 0.15, 0.7, 0.03], facecolor=axcolor)
    ax_ns = plt.axes([0.12, 0.09, 0.7, 0.03], facecolor=axcolor)

    # delay slider snaps to powers of two (log2 exponent), noise slider linear
    # ------------------------------------------------------------------------
    p0 = int(round(np.log2(delay0)))
    s_d = Slider(ax_d, 'delay (2^p)', 1, 10, valinit=p0, valstep=1)
    s_ns = Slider(ax_ns, 'noise sigma', 0.0, gen_kwargs['amplitude']/2,
                  valinit=gen_kwargs['noise_sigma'], valstep=5.0)

    # helper function to recompute moving average
    def recompute(_=None):
        # delay is a power of two
        shifter = int(s_d.val)
        delay = 1 << shifter

        # current
        nsy = state['noisy']

        # recompute shaper output with live slider values
        y0 = moving_average(nsy, delay, out_shift=shifter)

        # update graph
        line_out.set_ydata(y0)
        ax_out.set_title(f'Fixed-Point Moving Average output  (delay={delay}, shift={shifter})')
        ax_out.set_ylim(y_min, y_max)
        fig.canvas.draw_idle()

    # helper function to recompute noise of input pulse
    def regen_noise(_=None):
        # recompute input with new noise
        kw = dict(gen_kwargs)
        kw['noise_sigma'] = s_ns.val
        _, cln, nsy, _ = generate_input(**kw)

        # new noise input, recompute output
        state['noisy'] = nsy
        ax_in.lines[0].set_ydata(nsy)
        recompute()

    # Update graph if sliders are changed
    s_d.on_changed(recompute)
    s_ns.on_changed(regen_noise)

    # keep slider refs alive for the lifetime of the figure
    return [s_d, s_ns]
