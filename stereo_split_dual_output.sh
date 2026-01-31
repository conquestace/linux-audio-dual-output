#!/bin/bash

# ==============================================================================
# PULSEAUDIO STEREO SPLITTER (WITH LATENCY CORRECTION)
# ==============================================================================
# Function: Splits default stereo stream:
#           LEFT Channel  -> Analog Line Out
#           RIGHT Channel -> Bluetooth A2DP
# Feature:  Adds latency offset to Bluetooth so Analog waits for it to sync.
# ==============================================================================

# --- CONFIGURATION ---
# Physical Sink Names
PHYSICAL_L="alsa_output.pci-0000_0d_00.4.analog-stereo"
PHYSICAL_R="bluez_sink.30_63_71_21_12_88.a2dp_sink"

# LATENCY OFFSET (IN MILLISECONDS)
# Increase this if Line Out is still hearing sound before Bluetooth.
# Decrease this if Line Out is starting too late.
BLUETOOTH_LATENCY_MS=500

# Virtual Sink Names
REMAP_L_NAME="virtual_left_remap"
REMAP_R_NAME="virtual_right_remap"
COMBINE_NAME="stereo_splitter_master"

# ------------------------------------------------------------------------------

function do_clean() {
    echo "Cleaning up modules..."
    
    # Unload Master
    pactl list short modules | grep "sink_name=$COMBINE_NAME" | cut -f1 | while read -r id; do
        pactl unload-module "$id"
    done

    # Unload Remaps
    pactl list short modules | grep -E "sink_name=$REMAP_L_NAME|sink_name=$REMAP_R_NAME" | cut -f1 | while read -r id; do
        pactl unload-module "$id"
    done
    
    # Reset Latency on Physical Bluetooth sink to 0 (clean state)
    echo "Resetting latency offset on Bluetooth device..."
    pactl set-sink-latency-offset "$PHYSICAL_R" 0
}

function do_on() {
    do_clean
    echo "Initializing stereo splitter with ${BLUETOOTH_LATENCY_MS}ms sync correction..."

    # 1. Apply Latency Offset to Physical Bluetooth Sink
    # Logic: We tell PA the Bluetooth sink is 'slow'. The Combine module
    # will then deliberately delay the Analog sink to match this timestamp.
    # Convert ms to microseconds for pactl
    OFFSET_US=$((BLUETOOTH_LATENCY_MS * 1000))
    pactl set-sink-latency-offset "$PHYSICAL_R" $OFFSET_US

    # 2. Load Remap for LEFT Channel (Analog)
    # Maps stream-Left to Physical-Left+Right (Mono mix)
    pactl load-module module-remap-sink \
        sink_name=$REMAP_L_NAME \
        master=$PHYSICAL_L \
        channels=2 \
        master_channel_map=front-left,front-right \
        channel_map=front-left,front-left \
        remix=no > /dev/null

    # 3. Load Remap for RIGHT Channel (Bluetooth)
    # Maps stream-Right to Physical-Left+Right (Mono mix)
    pactl load-module module-remap-sink \
        sink_name=$REMAP_R_NAME \
        master=$PHYSICAL_R \
        channels=2 \
        master_channel_map=front-left,front-right \
        channel_map=front-right,front-right \
        remix=no > /dev/null

    # 4. Combine them
    pactl load-module module-combine-sink \
        sink_name=$COMBINE_NAME \
        slaves=$REMAP_L_NAME,$REMAP_R_NAME \
        channels=2 \
        channel_map=front-left,front-right \
        adjust_time=1 \
        resample_method=trivial > /dev/null

    # 5. Set Default
    pactl set-default-sink $COMBINE_NAME
    
    echo "DONE. Master Splitter Active."
    echo "Latency Correction: ${BLUETOOTH_LATENCY_MS}ms applied to $PHYSICAL_R"
}

function do_status() {
    echo "--- Active Modules ---"
    pactl list short modules | grep -E "$REMAP_L_NAME|$REMAP_R_NAME|$COMBINE_NAME"
    echo ""
    echo "--- Bluetooth Latency Offset ---"
    pactl list sinks | grep -A 20 "$PHYSICAL_R" | grep "Latency Offset"
}

# --- MAIN EXECUTION ---
case "$1" in
    on) do_on ;;
    off|clean) 
        do_clean 
        pactl set-default-sink $PHYSICAL_L
        echo "System restored."
        ;;
    status) do_status ;;
    *) echo "Usage: $0 {on|off|clean|status}"; exit 1 ;;
esac
