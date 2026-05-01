#!/usr/bin/env bash
# tests/test_parse_snapshot.sh — exercises wizard/_parse-snapshot.sh against
# synthetic log files we control.

# shellcheck disable=SC1091
source "$REPO_ROOT/wizard/lib.sh"

PARSE="$REPO_ROOT/wizard/_parse-snapshot.sh"

# Helper: write a sample log file containing one snapshot.
write_sample_log() {
  local f="$1"
  cat > "$f" <<'EOF'
2026-04-30 18:15:59 INFO  av-pain-reliever loaded (obs-cmd: /opt/homebrew/bin/obs-cmd)
2026-04-30 18:15:59 INFO  --- audio devices ---
2026-04-30 18:15:59 INFO    "MacBook Pro Microphone"  in=true out=false
2026-04-30 18:15:59 INFO    "MacBook Pro Speakers"  in=false out=true
2026-04-30 18:15:59 INFO    "Yeti Stereo Microphone"  in=true out=false
2026-04-30 18:15:59 INFO    "Microsoft Teams Audio"  in=true out=true
2026-04-30 18:15:59 INFO  --- attached USB devices ---
2026-04-30 18:15:59 INFO    vid=0x1e4e pid=0x701f  "HDMI to U3 capture"
2026-04-30 18:15:59 INFO    vid=0x2188 pid=0x6533  "CalDigit Thunderbolt 3 Audio"
2026-04-30 18:15:59 INFO    vid=0x05ac pid=0x024f  "Keychron K3"
2026-04-30 18:15:59 INFO  --- end snapshot ---
2026-04-30 18:15:59 INFO  applying profile: home-office
EOF
}

test_parse_emits_audio_section() {
  write_sample_log log.txt
  "$PARSE" log.txt > out.txt
  assert_file_contains out.txt '^AUDIO$'
}

test_parse_emits_usb_section() {
  write_sample_log log.txt
  "$PARSE" log.txt > out.txt
  assert_file_contains out.txt '^USB$'
}

test_parse_extracts_audio_names_with_in_out_flags() {
  write_sample_log log.txt
  "$PARSE" log.txt > out.txt
  # MacBook Pro Microphone is input-only
  assert_file_contains out.txt 'MacBook Pro Microphone	in	$'
  # MacBook Pro Speakers is output-only
  assert_file_contains out.txt 'MacBook Pro Speakers		out$'
  # Microsoft Teams Audio is both
  assert_file_contains out.txt 'Microsoft Teams Audio	in	out$'
}

test_parse_extracts_usb_with_bare_hex() {
  write_sample_log log.txt
  "$PARSE" log.txt > out.txt
  # USB lines emit BARE hex (no 0x prefix)
  assert_file_contains out.txt '^1e4e	701f	HDMI to U3 capture$'
  assert_file_contains out.txt '^2188	6533	CalDigit Thunderbolt 3 Audio$'
  assert_file_contains out.txt '^05ac	024f	Keychron K3$'
}

test_parse_no_log_file_exits_2() {
  assert_exit_code 2 "$PARSE" /nonexistent/path
}

test_parse_log_without_snapshot_exits_1() {
  cat > log.txt <<'EOF'
2026-04-30 18:00:00 INFO  startup
2026-04-30 18:00:01 INFO  some other line
EOF
  assert_exit_code 1 "$PARSE" log.txt
}

test_parse_uses_most_recent_snapshot_when_multiple() {
  cat > log.txt <<'EOF'
2026-04-30 18:00:00 INFO  --- audio devices ---
2026-04-30 18:00:00 INFO    "OLD DEVICE"  in=true out=false
2026-04-30 18:00:00 INFO  --- attached USB devices ---
2026-04-30 18:00:00 INFO    vid=0xdead pid=0xbeef  "Old USB"
2026-04-30 18:00:00 INFO  --- end snapshot ---
2026-04-30 19:00:00 INFO  --- audio devices ---
2026-04-30 19:00:00 INFO    "NEW DEVICE"  in=true out=false
2026-04-30 19:00:00 INFO  --- attached USB devices ---
2026-04-30 19:00:00 INFO    vid=0xc0de pid=0xcafe  "New USB"
2026-04-30 19:00:00 INFO  --- end snapshot ---
EOF
  "$PARSE" log.txt > out.txt
  assert_file_contains out.txt 'NEW DEVICE'
  assert_file_contains out.txt 'c0de	cafe	New USB'
  assert_file_not_contains out.txt 'OLD DEVICE'
  assert_file_not_contains out.txt 'dead	beef'
}

test_parse_handles_unnamed_usb_devices() {
  cat > log.txt <<'EOF'
2026-04-30 18:15:59 INFO  --- audio devices ---
2026-04-30 18:15:59 INFO    "Mic"  in=true out=false
2026-04-30 18:15:59 INFO  --- attached USB devices ---
2026-04-30 18:15:59 INFO    vid=0x043e pid=0x9a71  "?"
2026-04-30 18:15:59 INFO  --- end snapshot ---
EOF
  "$PARSE" log.txt > out.txt
  # Unnamed devices (productName "?") should still parse — the "?" is the name.
  assert_file_contains out.txt '^043e	9a71	\?$'
}

test_parse_does_not_pick_up_USB_added_log_lines() {
  # Lines like "USB added: Foo (vid=... pid=...)" appear after the snapshot
  # block. The parser must NOT include them in the USB section.
  cat > log.txt <<'EOF'
2026-04-30 18:15:59 INFO  --- audio devices ---
2026-04-30 18:15:59 INFO    "Mic"  in=true out=false
2026-04-30 18:15:59 INFO  --- attached USB devices ---
2026-04-30 18:15:59 INFO    vid=0x1111 pid=0x2222  "InSnapshot"
2026-04-30 18:15:59 INFO  --- end snapshot ---
2026-04-30 18:16:00 INFO  USB added: NotInSnapshot (vid=3333 pid=4444)
EOF
  "$PARSE" log.txt > out.txt
  assert_file_contains out.txt 'InSnapshot'
  assert_file_not_contains out.txt 'NotInSnapshot'
}
