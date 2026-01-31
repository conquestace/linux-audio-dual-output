#!/bin/bash

# ==============================================================================
# PULSEAUDIO 3-WAY SPLITTER (L + R + CENTER/SUB)
# ==============================================================================
# 1. LEFT Channel  -> Physical Sink 1
# 2. RIGHT Channel -> Physical Sink 2
# 3. FULL MIX      -> Physical Sink 3 (Plays everything - good for Sub/Center)
# ==============================================================================

# --- CONFIGURATION ---

# 1. LEFT SPEAKER (Analog Line Out)
PHYSICAL_1="bluez_sink.D4_F5_47_D4_DF_07.a2dp_sink"

# 2. RIGHT SPEAKER (Bluetooth)
PHYSICAL_2="bluez_sink.30_63_71_21_12_88.a2dp_sink"
LATENCY_2_MS=0  # Latency for Speaker 2 (0 if wired, ~200 if bluetooth)

# 3. THIRD SPEAKER (The new one)
# Run 'pactl list short sinks' to find this name
PHYSICAL_3="alsa_output.pci-0000_0d_00.4.analog-stereo"
LATENCY_3_MS=0    # Latency for Speaker 3 (0 if wired)

# Virtual Internal Names
REMAP_1="virtual_left_remap"
REMAP_2="virtual_right_remap"
REMAP_3="virtual_center_remap"
COMBINE_NAME="tri_splitter_master"

# ------------------------------------------------------------------------------

function do_clean() {
    echo "Cleaning up modules..."
    # Unload Master
    pactl list short modules | grep "sink_name=$COMBINE_NAME" | cut -f1 | while read -r id; do
        pactl unload-module "$id"
    done
    # Unload Remaps
    pactl list short modules | grep -E "sink_name=$REMAP_1|sink_name=$REMAP_2|sink_name=$REMAP_3" | cut -f1 | while read -r id; do
        pactl unload-module "$id"
    done
    
    # Reset Latencies
    pactl set-sink-latency-offset "$PHYSICAL_2" 0
    pactl set-sink-latency-offset "$PHYSICAL_3" 0
}

function do_on() {
    do_clean
    echo "Initializing 3-way splitter..."

    # 1. Apply Latencies
    OFFSET_2_US=$((LATENCY_2_MS * 1000))
    OFFSET_3_US=$((LATENCY_3_MS * 1000))
    pactl set-sink-latency-offset "$PHYSICAL_2" $OFFSET_2_US
    pactl set-sink-latency-offset "$PHYSICAL_3" $OFFSET_3_US

    # 2. Remap Speaker 1 (LEFT ONLY)
    pactl load-module module-remap-sink \
        sink_name=$REMAP_1 master=$PHYSICAL_1 channels=2 \
        master_channel_map=front-left,front-right \
        channel_map=front-left,front-left remix=no > /dev/null

    # 3. Remap Speaker 2 (RIGHT ONLY)
    pactl load-module module-remap-sink \
        sink_name=$REMAP_2 master=$PHYSICAL_2 channels=2 \
        master_channel_map=front-left,front-right \
        channel_map=front-right,front-right remix=no > /dev/null

    # 4. Remap Speaker 3 (FULL MIX - L+R)
    # We use standard mapping here so it hears everything
    pactl load-module module-remap-sink \
        sink_name=$REMAP_3 master=$PHYSICAL_3 channels=2 \
        master_channel_map=front-left,front-right \
        channel_map=front-left,front-right remix=yes > /dev/null

    # 5. Combine All Three
    pactl load-module module-combine-sink \
        sink_name=$COMBINE_NAME \
        slaves=$REMAP_1,$REMAP_2,$REMAP_3 \
        channels=2 \
        channel_map=front-left,front-right \
        adjust_time=1 resample_method=trivial > /dev/null

    # 6. Activate
    pactl set-default-sink $COMBINE_NAME
    echo "DONE. 3-Way Splitter Active."
}

# --- MAIN EXECUTION ---
case "$1" in
    on) do_on ;;
    off|clean) 
        do_clean 
        pactl set-default-sink $PHYSICAL_1
        echo "System restored."
        ;;
    status) 
        echo "--- Active Modules ---"
        pactl list short modules | grep -E "$COMBINE_NAME|$REMAP_1"
        ;;
    *) echo "Usage: $0 {on|off|clean|status}"; exit 1 ;;
esac
