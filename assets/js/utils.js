// Format tanggal ke YYYY-MM-DD
function formatDate(date = new Date()) {
  return date.toISOString().split('T')[0];
}

// Format timestamp ke datetime lokal
function formatTimestamp(ts) {
  if (!ts) return '-';
  const d = new Date(ts);
  return d.toLocaleString('id-ID');
}

// Cek apakah status aktif dan belum expired
function isActiveLicense(license) {
  if (!license || license.status !== 'ACTIVE') return false;
  return Date.now() < license.expiry_date;
}

// Hitung sisa hari
function daysRemaining(expiryDate) {
  const diff = expiryDate - Date.now();
  return Math.max(0, Math.floor(diff / (1000 * 60 * 60 * 24)));
}

// Tampilkan toast sederhana
function showToast(message, type = 'success') {
  const toast = document.createElement('div');
  toast.className = `fixed bottom-4 right-4 px-4 py-2 rounded-lg shadow-lg text-white ${type === 'error' ? 'bg-red-500' : 'bg-green-500'} z-50`;
  toast.innerText = message;
  document.body.appendChild(toast);
  setTimeout(() => toast.remove(), 3000);
}