# The board's roots

`roots.pem` is the store of root certificates L0S's TLS client checks a
server's chain to, staged as `/etc/ssl/roots.pem` in the demo's and the
Pi 5's initramfs (`stage_etc` in the Makefile). It is Mozilla's CA
bundle, as NSS 3.132's `certdata.txt` gives it (118 roots, those trusted
for TLS servers), taken from Arch Linux's `ca-certificates-mozilla`
3.132-1.1 on 2026-11-05. The certificates are public; the bundle is
distributed by Mozilla under the Mozilla Public License 2.0.

To refresh it, copy a newer Mozilla bundle over it, PEM, one
`-----BEGIN CERTIFICATE-----` block a root (comment lines between are
passed over), and check that `make test` still passes: `trust_test.l0`
pins its own roots and does not read this file.
