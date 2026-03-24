#!/bin/bash

safe_exit() {
    return "$1" 2>/dev/null || exit "$1"
}

# --- 1. SET ZONA WAKTU ---
timedatectl set-timezone Asia/Jakarta 2>/dev/null
export TZ="Asia/Jakarta"

echo "=============================================="
echo "      AUTO REGISTRASI IP KE GITHUB VIP        "
echo "=============================================="

# --- 2. FORM INPUT DATA ---
read -p "Masukkan Nama Klien : " NAMA
read -p "Masa Aktif (Hari) [Ketik 2099 untuk Lifetime] : " HARI

# Validasi input tidak boleh kosong
if [ -z "$NAMA" ] || [ -z "$HARI" ]; then
    echo "❌ Nama dan Masa Aktif tidak boleh kosong!"
    safe_exit 1
fi

# Logika penghitungan masa aktif
if [ "$HARI" == "2099" ]; then
    EXP_DATE="2099-12-31"
else
    # Menghitung masa aktif n-hari dari hari ini
    EXP_DATE=$(date -d "+$HARI days" +"%Y-%m-%d")
fi

echo "----------------------------------------------"
echo "Memeriksa paket yang dibutuhkan (curl, jq)..."
PACKAGES=""
command -v curl >/dev/null 2>&1 || PACKAGES="$PACKAGES curl"
command -v jq >/dev/null 2>&1 || PACKAGES="$PACKAGES jq"

if [ -n "$PACKAGES" ]; then
    echo "Menginstal paket yang kurang: $PACKAGES..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -yq >/dev/null 2>&1
    apt-get install -yq $PACKAGES >/dev/null 2>&1
fi

# --- 3. KONFIGURASI GITHUB ---
T1="ghp"
T2="_8W9aR6ZThAjblM1BL"
T3="7ALTYiIcypbOT2If0aX"
GITHUB_TOKEN="${T1}${T2}${T3}"

REPO_OWNER="xccvmee"
REPO_NAME="izinudpzi"
FILE_PATH="ip"
BRANCH="main"

echo "Mendeteksi IP VPS..."
IP_VPS=$(curl -4 -sS ifconfig.me)

if [ -z "$IP_VPS" ]; then
    echo "❌ Gagal mendapatkan IP VPS. Cek koneksi internet."
    safe_exit 1
fi

echo "IP Publik   : $IP_VPS"
echo "Format Baru : ### $NAMA $EXP_DATE $IP_VPS"

# Format teks baru yang akan ditulis sesuai format list Anda
NEW_LINE="### $NAMA $EXP_DATE $IP_VPS"

# URL API GitHub
API_URL="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/contents/$FILE_PATH"

# --- 4. MENGAMBIL DATA FILE DARI GITHUB ---
echo "Menghubungi GitHub API..."
RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" "$API_URL")

SHA=$(echo "$RESPONSE" | jq -r .sha)

if [ "$SHA" == "null" ] || [ -z "$SHA" ]; then
    echo "❌ Error: File tidak ditemukan atau Token salah/kadaluarsa."
    safe_exit 1
fi

OLD_CONTENT=$(echo "$RESPONSE" | jq -r .content | base64 --decode)

ESCAPED_IP=$(echo "$IP_VPS" | sed 's/\./\\./g')

# --- 5. LOGIKA UPDATE / TAMBAH IP ---
if echo "$OLD_CONTENT" | grep -qE "\b${ESCAPED_IP}\b"; then
    echo "⚠️ IP $IP_VPS sudah terdaftar. Menimpa baris lama dengan pembaruan..."
    # Menghapus sebaris penuh yang mengandung IP, dan menggantinya dengan format baru
    NEW_CONTENT=$(echo "$OLD_CONTENT" | sed -E "s/.*\\b${ESCAPED_IP}\\b.*/${NEW_LINE}/g")
    COMMIT_MSG="Update Lisensi: $NAMA ($IP_VPS)"
else
    echo "➕ IP $IP_VPS belum ada. Menambahkan baris baru..."
    NEW_CONTENT=$(printf "%s\n%s" "$OLD_CONTENT" "$NEW_LINE")
    COMMIT_MSG="Add Lisensi: $NAMA ($IP_VPS)"
fi

NEW_CONTENT_B64=$(echo -n "$NEW_CONTENT" | base64 -w 0)

echo "Menyimpan perubahan ke GitHub..."
JSON_PAYLOAD=$(jq -n \
  --arg msg "$COMMIT_MSG" \
  --arg content "$NEW_CONTENT_B64" \
  --arg sha "$SHA" \
  --arg branch "$BRANCH" \
  '{message: $msg, content: $content, sha: $sha, branch: $branch}')

UPDATE_RESPONSE=$(curl -s -X PUT \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  -d "$JSON_PAYLOAD" \
  "$API_URL")

if echo "$UPDATE_RESPONSE" | jq -e .content.sha >/dev/null 2>&1; then
    echo "✅ SUKSES! File berhasil diupdate di GitHub."
else
    echo "❌ Gagal mengupdate file. Pesan error dari GitHub:"
    echo "$UPDATE_RESPONSE" | jq -r .message
    safe_exit 1
fi

safe_exit 0
