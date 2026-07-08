"""
Computes shaper reference outputs and dump the VHDL stimulus files.

Run:  python run_export.py
"""

import matplotlib.pyplot as plt

from shapers import *
from vhdl_export import *

def main():

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
    PLOT_ENABLE = 1                 # plot what we are exporting

    # ------------------------------------------------------------------------
    # Workspace
    # ------------------------------------------------------------------------
    t, clean, noisy, Tclk = generate_input(n_samples=n_samples, fs=fs, amplitude=amplitude, tau_rise_s=tau_rise_s, tau_decay_s=tau_decay_s,
                                        noise_offset=noise_offset, noise_sigma=noise_sigma)
    noisy_signed = -1 * noisy

    # select shaper:
    if SHAPER_SELECT == 1:
        y0 = jordanov_trapezoidal(noisy, k0, m0, M0, out_shift=out_shift0)
        y0_signed = jordanov_trapezoidal(noisy_signed, k0, m0, M0, out_shift=out_shift0)
    else:
        y0 = moving_average(noisy, delay, out_shift=shifter, signed_input= False)
        y0_signed = moving_average(noisy_signed, delay, out_shift=shifter, signed_input= True)

    # Export unsigned discrete signals to vhdl
    export_for_vhdl(noisy, y0,
                data_width=14, out_width=14,
                in_signed=False, out_signed=False,
                filename="noisy_pulse_14b_unsigned.txt")
    
    # Export signed discrete signals to vhdl
    export_for_vhdl(noisy_signed, y0_signed,
                data_width=15, out_width=15,
                in_signed=True, out_signed=True,
                filename="noisy_pulse_15b_signed.txt")
    
    # ------------------------------------------------------------------------
    # Quick plot 
    # ------------------------------------------------------------------------

    if PLOT_ENABLE:
        fig, ax = plt.subplots(2, 2, figsize=(11, 6), sharex=True)
    
        # top row
        ax[0, 0].plot(noisy, lw=0.7, color='0.5')
        ax[0, 0].set_title('unsigned input (14b)')
        ax[0, 1].plot(y0, lw=0.9, color='tab:red')
        ax[0, 1].set_title('unsigned output (14b)')
    
        # bottom row
        ax[1, 0].plot(noisy_signed, lw=0.7, color='0.5')
        ax[1, 0].set_title('signed input (15b)')
        ax[1, 1].plot(y0_signed, lw=0.9, color='tab:red')
        ax[1, 1].set_title('signed output (15b)')
    
        for a in ax.flat:
            a.grid(True, alpha=0.3)
        ax[1, 0].set_xlabel('sample n')
        ax[1, 1].set_xlabel('sample n')
        fig.suptitle('Exported signal outputs')
        fig.tight_layout()
    
        plt.show()


if __name__ == '__main__':
    main()
