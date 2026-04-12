// Untuk investor dashboard
async function loadInvestorDashboard() {
  const urlParams = new URLSearchParams(window.location.search);
  const accountNumber = urlParams.get('account');
  if (!accountNumber) {
    document.getElementById('content').innerHTML = '<div class="text-red-500">Parameter account tidak ditemukan.</div>';
    return;
  }
  const licenseRef = firebase.database().ref(`licenses/${accountNumber}`);
  licenseRef.on('value', (snap) => {
    const license = snap.val();
    if (!license) {
      document.getElementById('content').innerHTML = '<div class="text-red-500">Lisensi tidak ditemukan.</div>';
      return;
    }
    const active = isActiveLicense(license);
    const remaining = daysRemaining(license.expiry_date);
    document.getElementById('accountNumber').innerText = accountNumber;
    document.getElementById('licenseKey').innerText = license.license_key;
    document.getElementById('membership').innerText = license.membership_type;
    document.getElementById('status').innerHTML = `<span class="px-2 py-1 rounded-full text-xs ${active ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'}">${license.status}</span>`;
    document.getElementById('expiry').innerText = formatTimestamp(license.expiry_date);
    document.getElementById('remaining').innerText = `${remaining} hari`;
    document.getElementById('heartbeat').innerText = formatTimestamp(license.last_heartbeat);
    if (license.vps_rental) {
      document.getElementById('vpsInfo').innerHTML = `<span class="text-blue-600">VPS Rental aktif (sisa cicilan: $${license.vps_remaining})</span>`;
    } else {
      document.getElementById('vpsInfo').innerHTML = '<span class="text-gray-500">Tidak menggunakan VPS Rental</span>';
    }
    // Peringatan jika mendekati expired (3 hari)
    if (remaining <= 3 && active) {
      document.getElementById('warningBanner').classList.remove('hidden');
    } else {
      document.getElementById('warningBanner').classList.add('hidden');
    }
  });
}