#!/bin/bash

set -e

# Install dependencies jika belum ada
if ! command -v nft >/dev/null 2>&1; then
    apt-get update
    apt-get install -y nftables
fi

if ! command -v curl >/dev/null 2>&1; then
    apt-get update
    apt-get install -y curl
fi

# Aktifkan nftables
systemctl enable nftables >/dev/null 2>&1 || true
systemctl start nftables >/dev/null 2>&1 || true

TABLE="inet filter"
SETNAME="geo_block"

TMP=$(mktemp)

echo "Downloading country lists..."

for cc in cn vn jp; do
    curl -fsSL "https://www.ipdeny.com/ipblocks/data/aggregated/${cc}-aggregated.zone" >> "$TMP"
done

sort -u "$TMP" -o "$TMP"

# Buat table jika belum ada
nft list table inet filter >/dev/null 2>&1 || \
    nft add table inet filter

# Hapus set lama
nft delete set inet filter $SETNAME 2>/dev/null || true

# Buat set baru
nft add set inet filter $SETNAME \
'{ type ipv4_addr; flags interval; }'

# Import CIDR
{
    printf "add element inet filter %s {\n" "$SETNAME"
    paste -sd, "$TMP"
    printf "\n}\n"
} | nft -f -

# Buat chain input jika belum ada
nft list chain inet filter input >/dev/null 2>&1 || \
nft add chain inet filter input \
'{ type filter hook input priority 0; policy accept; }'

# Tambah rule drop jika belum ada
if ! nft list chain inet filter input | grep -q "@$SETNAME"; then
    nft add rule inet filter input ip saddr @$SETNAME drop
fi

COUNT=$(wc -l < "$TMP")

echo "Loaded $COUNT CIDR into $SETNAME"

rm -f "$TMP"
