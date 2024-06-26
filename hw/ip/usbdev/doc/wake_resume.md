# USBDEV Suspending and Resuming with Sleep / Low Power Modes

# Overview

This document outlines a recipe for going in and out of low power modes for suspending and resuming, respectively.
It assumes the design uses the `usbdev_aon_wake` and `pinmux` modules to handle critical signals in low-power mode like `top_earlgrey`.

The `pinmux` module ensures the D+ and D- pins are high-Z / input only.
The `usbdev_aon_wake` module maintains the pull-up state, monitors the D+ and D- pins for events to leave the suspended state, and provides the wake-up signal.

Note that this procedure to hand control over to `usbdev_aon_wake` does not apply if there is no intention to go to a low-power mode.

## Suspending from Active

### Configuration

0. Software configures the sleep state for usbdev DIOs to be high-Z (input only), in the `pinmux`.

### Suspending

1. The `usbdev_linkstate` module detects the line has been at idle for at least 3 ms, issues `link_suspend_o`, and transitions to the `LinkSuspended` state.
   - The protocol engine begins ignoring transactions.
     Any non-idle signaling kicks off the process to resume.
   - The USB differential receiver is turned off, if it was controlled by the `rx_enable_o` pin.
   - Software receives the event for going into the suspended state in [`intr_state.link_suspend`](../data/usbdev.hjson#intr_state).
2. Software hands control to the AON module.
   - Software writes a `1` to [`wake_control.suspend_req`](../data/usbdev.hjson#wake_control).
   - The AON module transitions to the active state and takes over the pullup enable.
     It begins monitoring for events that trigger waking / resuming / resetting.
3. Software prepares for deep sleep.
   - It saves the current "device state" in the AON retention RAM, including the current configuration and device address (if any).
   - In order to restore open data pipes to their current state upon return from a sleep state, the software must also capture the current
     state of all relevant Data Toggle bits by reading from the [`in_data_toggle`](registers.md#in_data_toggle) and [`out_data_toggle`](registers.md#out_data_toggle) registers.
   - The `usbdev_linkstate` module is still powered and monitoring events, and it can resume at any time.
     Note that if a resume event does occur before the point of no return, software need only set [`wake_control.wake_ack`](../data/usbdev.hjson#wake_control) to restore control to `usbdev`.
   - Software also does any other tasks for preparing for deep sleep, such as enabling USB events to wake the chip.
4. Software begins deep sleep.
   - This is the likely the point of no return.
   - It turns off non-AON clocks and power.
   - As it is now unpowered, the `usbdev_linkstate` module is inactive.
     The AON module is now the only device monitoring for USB events.

### Resuming

1. Software determines whether it is waking due to USB.
   - If the low-power state was never entered, software merely unwinds / drops the deep sleep preparation and skips to step 6.
2. Software pulls configuration data from the AON retention RAM and restores information about the USB device state.
3. Software sets up and connects usbdev.
   - The `usbdev_linkstate` module should hold in the LinkPowered state, waiting for a bus reset.
     It is now monitoring events alongside the AON module.
4. Software releases the DIOs from sleep mode.
5. Software checks the AON events and identifies the correct state transition.
6. Software issues [`wake_control.wake_ack`](../data/usbdev.hjson#wake_control) to the AON module.
   - The AON module stops monitoring events and controlling the pull-ups, restoring control to the full-power `usbdev` module.
   - The AON module also clears the stored events.
     Events that occurred between reading the stored values in the AON module and acknowledging the wake-up are captured in the `usbdev_linkstate` module.
7. If software determined the state transition should be back to an active state, software issues [`usbctrl.resume_link_active`](../data/usbdev.hjson#usbctrl).
   - After going to low-power, it's not clear to the hardware whether it needs a bus reset to transition out of the `LinkPowered` state.
     Software's saved state in the AON retention RAM should provide this information, and the CSR write provides a bypass mechanism.
   - The `usbdev_linkstate` module transitions from `LinkPowered` to `LinkResuming` state.
8. The upstream hub stops signaling K to resume.
   - The `usbdev_linkstate` module transitions from `LinkResuming` to `LinkActiveNoSOF` state, and USB is active once again.
9. In order to restore all data pipes to their pre-sleep state and resume communication with the USB host, the Data Toggle bits must be restored by setting them to the values captured when suspending.
   - Writing to the [`in_data_toggle`](registers.md#in_data_toggle) and [`out_data_toggle`](registers.md#out_data_toggle) registers prevents subsequent packets being ignored as retransmission attempts.


## Operation without Sleep / Lower Power modes

If the USB device is to be deployed without support for sleep/low power modes, or without a requirement to maintain the state of the USB during such a state, then there is no requirement for the external `usbdev_aon_wake` module to be present. It is a simple matter to tie the `usb_aon_wake_detect_active_i` signal low, along with the three status indication signals (`usb_aon_bus_reset_i`, `usb_aon_sense_lost_i` and `usb_aon_bus_not_idle_i`) that would normally indicate to software the reason for waking from a sleep/low power state.
