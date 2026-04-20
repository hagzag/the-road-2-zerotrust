# Part 1 — Trusted Wires: Capture Your Own telnet Password

**Companion lab for**: [From Trusted Wires to the Open Internet](https://portfolio.hagzag.com/blog/from-trusted-wires-to-the-open-internet/)
**Series**: [The Road to Zero Trust](../../README.md)
**Estimated time**: 5 minutes
**Prereqs**: Docker, [`k3d`](https://k3d.io), `kubectl`, and Wireshark (or `tshark`)

## What you'll see

A two-container Pod on a local k3d cluster running `telnetd` side-by-side with `tcpdump`. You'll telnet in, type a password, then open the captured `.pcap` and read your own credentials in ASCII. The point isn't *"telnet is insecure"* — you already know that. The point is feeling, in your hands, how much of the 1990s trust model lived at the physical layer.

## Run it

```bash
# from this directory
./run.sh
```

That's it. The script creates a cluster called `trusted-wire`, applies `telnet-demo.yaml`, prints instructions to telnet in, and tells you how to pull the pcap.

### Step-by-step (if you'd rather drive manually)

```bash
# 1. Local cluster
k3d cluster create trusted-wire --agents 1

# 2. telnetd + tcpdump sidecar on one Pod
kubectl apply -f telnet-demo.yaml
kubectl wait --for=condition=Ready pod/telnet-demo --timeout=60s

# 3. Telnet in (in another terminal) and log in as the demo user
kubectl exec -it telnet-demo -c client -- \
  sh -c "telnet 127.0.0.1 23"
#   login: demo
#   password: demo

# 4. Stop the capture and pull the pcap
kubectl exec telnet-demo -c sniffer -- pkill -INT tcpdump || true
kubectl cp telnet-demo:/tmp/telnet.pcap ./telnet.pcap -c sniffer

# 5. Read the password in ASCII
wireshark ./telnet.pcap     # Right-click the stream → Follow → TCP Stream
# or, without a GUI:
tshark -r ./telnet.pcap -q -z follow,tcp,ascii,0
```

The "Follow TCP Stream" view shows the entire interactive session — including the password you just typed, letter by letter.

## Cleanup

```bash
./cleanup.sh
# or
k3d cluster delete trusted-wire
```

## What's actually happening

- The Pod runs with `shareProcessNamespace: true`, so the sniffer container can see the `telnetd` traffic on the shared loopback interface. In a real multi-host setup, `tcpdump` would run on a tap or span port — but the educational point (cleartext on the wire) is identical.
- The telnet server image is a standard BusyBox-based one with a preset `demo:demo` user so you don't have to configure PAM.
- The pcap is written to an `emptyDir` volume shared between containers, so `kubectl cp` from the sniffer picks it up cleanly.

## File layout

```
practice/part1/
├── README.md              ← this file
├── telnet-demo.yaml       ← single-Pod manifest (telnetd + sniffer + client)
├── run.sh                 ← one-shot runner
└── cleanup.sh             ← tear-down
```

## Takeaway questions

After running the lab, try to answer these out loud before you move on to Part 2 (SSH):

1. **Which OSI layer(s) does telnet's "security" depend on?** (Answer: L1–L3 — the physical wire and the routed network.)
2. **What changes about this threat model if the Pod is scheduled on a shared multi-tenant node?** (Answer: `shareProcessNamespace` + a malicious co-tenant ≈ the 1990s "helpful sysadmin with a packet sniffer" problem.)
3. **Why was this protocol design rational in 1988 and broken by 1998?** (Answer: the wire stopped being a boundary the operator controlled.)

## Next

→ [Part 2 — SSH and the Cryptographic Turn](../part2/) *(coming next)*
