#!/usr/bin/env python3
"""
OpenVPN handshake fingerprinter.

Reads a pcap, walks UDP/1194 packets, decodes the top-5-bits opcode byte,
and prints an opcode histogram and a DPI-style verdict.

Usage:
    python3 classify.py path/to/openvpn.pcap

Requires: scapy (`pip install scapy`).
"""
from __future__ import annotations

import sys
from collections import Counter

try:
    from scapy.all import rdpcap, UDP, Raw
except ImportError:
    sys.stderr.write("This script needs scapy: pip install scapy\n")
    sys.exit(2)

OPCODES = {
    1: "P_CONTROL_HARD_RESET_CLIENT_V1",
    2: "P_CONTROL_HARD_RESET_SERVER_V1",
    3: "P_CONTROL_SOFT_RESET_V1",
    4: "P_CONTROL_V1",
    5: "P_ACK_V1",
    6: "P_DATA_V1",
    7: "P_CONTROL_HARD_RESET_CLIENT_V2",
    8: "P_CONTROL_HARD_RESET_SERVER_V2",
    9: "P_DATA_V2",
    10: "P_CONTROL_HARD_RESET_CLIENT_V3",
}


def classify(pcap_path: str) -> int:
    pkts = rdpcap(pcap_path)
    udp_1194 = [p for p in pkts
                if UDP in p and (p[UDP].dport == 1194 or p[UDP].sport == 1194)]

    if not udp_1194:
        print("No UDP/1194 packets found. Did you capture the right flow?")
        return 1

    hist: Counter[str] = Counter()
    saw_client_reset = False
    saw_server_reset = False

    for pkt in udp_1194:
        if Raw not in pkt:
            continue
        payload = bytes(pkt[Raw].load)
        if not payload:
            continue
        opcode = (payload[0] >> 3) & 0x1F
        name = OPCODES.get(opcode, f"UNKNOWN({opcode})")
        hist[name] += 1
        if opcode in (1, 7, 10):
            saw_client_reset = True
        if opcode in (2, 8):
            saw_server_reset = True

    print(f"Total UDP/1194 packets: {len(udp_1194)}")
    for name, count in hist.most_common():
        print(f"  {name:<34}: {count}")

    known = sum(v for k, v in hist.items() if not k.startswith("UNKNOWN"))
    known_ratio = known / max(1, sum(hist.values()))

    if saw_client_reset and saw_server_reset and known_ratio > 0.8:
        confidence = 95
        verdict = "OpenVPN handshake"
    elif known_ratio > 0.6:
        confidence = 70
        verdict = "Likely OpenVPN (handshake partial / re-keying)"
    else:
        confidence = 30
        verdict = "Unknown / not OpenVPN"

    print(f"\nVerdict: {verdict} ({confidence}% confidence)")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: classify.py <pcap>", file=sys.stderr)
        sys.exit(2)
    sys.exit(classify(sys.argv[1]))
