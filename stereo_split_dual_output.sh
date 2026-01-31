#!/bin/bash

# ==============================================================================
# PULSEAUDIO STEREO SPLITTER
# ==============================================================================
# Function: Splits the default stereo stream into two physical devices.
#           LEFT Channel  -> Analog Line Out (Mono-mixed to both drivers)
#           RIGHT Channel -> Bluetooth A2DP  (Mono-mixed to both drivers)
# ==============================================================================

# --- CONFIGURATION ---
# Physical Sink Names (As provided)
PHYSICAL_L="alsa_output.pci-0000_0d_00.4.analog-stereo"
PHYSICAL_R="bluez_sink.30_63_71_21_12_88.a2dp_sink"

# Virtual Sink Names (Internal logic)
REMAP_L_NAME="virtual_left_remap"
REMAP_R_NAME="virtual_right_remap"
COMBINE_NAME="stereo_splitter_master"

# ------------------------------------------------------------------------------

function do_clean() {
    echo "Cleaning up existing splitter modules..."
    
    # Find and unload modules related to our specific sink names
    # We grep for the sink names we defined to find the module IDs
    
    pactl list short modules | grep "sink_name=$COMBINE_NAME" | cut -f1 | while read -r id; do
        echo "Unloading Combine Module ID: $id"
        pactl unload-module "$id"
    done

    pactl list short modules | grep "sink_name=$REMAP_L_NAME" | cut -f1 | while read -r id; do
        echo "Unloading Left Remap Module ID: $id"
        pactl unload-module "$id"
    done

    pactl list short modules | grep "sink_name=$REMAP_R_NAME" | cut -f1 | while read -r id; do
        echo "Unloading Right Remap Module ID: $id"
        pactl unload-module "$id"
    done
}

function do_on() {
    # 1. Clean first to avoid duplicates
    do_clean

    echo "initializing stereo splitter..."

    # 2. Load Remap for LEFT Channel
    # Logic: Take 'front-left' from the stream, send it to 'front-left,front-right' of Physical Device A
    echo "Loading Left Channel Map -> $PHYSICAL_L"
    pactl load-module module-remap-sink \
        sink_name=$REMAP_L_NAME \
        master=$PHYSICAL_L \
        channels=2 \
        master_channel_map=front-left,front-right \
        channel_map=front-left,front-left \
        remix=no

    # 3. Load Remap for RIGHT Channel
    # Logic: Take 'front-right' from the stream, send it to 'front-left,front-right' of Physical Device B
    echo "Loading Right Channel Map -> $PHYSICAL_R"
    pactl load-module module-remap-sink \
        sink_name=$REMAP_R_NAME \
        master=$PHYSICAL_R \
        channels=2 \
        master_channel_map=front-left,front-right \
        channel_map=front-right,front-right \
        remix=no

    # 4. Combine them into one Stereo Sink
    # Logic: When audio is played here, L goes to REMAP_L, R goes to REMAP_R
    echo "Creating Master Splitter Sink..."
    pactl load-module module-combine-sink \
        sink_name=$COMBINE_NAME \
        slaves=$REMAP_L_NAME,$REMAP_R_NAME \
        channels=2 \
        channel_map=front-left,front-right

    # 5. Set as Default
    echo "Setting $COMBINE_NAME as default sink..."
    pactl set-default-sink $COMBINE_NAME

    echo "Done! 'Stereo Splitter Master' is now active."
}

function do_status() {
    echo "--- Active Splitter Modules ---"
    pactl list short modules | grep -E "$REMAP_L_NAME|$REMAP_R_NAME|$COMBINE_NAME"
    
    echo ""
    echo "--- Current Default Sink ---"
    pactl info | grep "Default Sink"
}

# --- MAIN EXECUTION ---

case "$1" in
    on)
        do_on
        ;;
    off|clean)
        do_clean
        # Optional: Reset default sink to the physical Line Out
        pactl set-default-sink $PHYSICAL_L
        echo "System reset to standard configuration."
        ;;
    status)
        do_status
        ;;
    *)
        echo "Usage: $0 {on|off|clean|status}"
        exit 1
        ;;
esac
