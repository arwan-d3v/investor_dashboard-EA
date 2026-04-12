let currentAccount = null;

async function loadMonitoring() {
  const searchBtn = document.getElementById('searchBtn');
  const accountInput = document.getElementById('accountSearch');
  searchBtn.addEventListener('click', () => {
    currentAccount = accountInput.value.trim();
    if (currentAccount) {
      loadAccountData(currentAccount);
    }
  });
}

async function loadAccountData(account) {
  const db = firebase.database();
  const licenseRef = db.ref(`licenses/${account}`);
  licenseRef.on('value', async (snap) => {
    const license = snap.val();
    if (!license) {
      document.getElementById('accountDetails').innerHTML = '<div class="text-red-500">Akun tidak ditemukan</div>';
      return;
    }
    // Overview
    document.getElementById('accNumber').innerText = account;
    document.getElementById('licenseStatus').innerHTML = `<span class="px-2 py-1 rounded-full ${license.status === 'ACTIVE' ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'}">${license.status}</span>`;
    document.getElementById('membershipType').innerText = license.membership_type;
    document.getElementById('expiryDate').innerText = formatTimestamp(license.expiry_date);
    document.getElementById('heartbeatTime').innerText = formatTimestamp(license.last_heartbeat);
    document.getElementById('vpsStatus').innerHTML = license.vps_rental ? `Aktif (sisa $${license.vps_remaining})` : 'Tidak';
    // Daily Summary
    const summarySnap = await db.ref(`licenses/${account}/daily_summary`).orderByKey().limitToLast(7).once('value');
    let tableRows = '';
    summarySnap.forEach((child) => {
      const data = child.val();
      tableRows += `<tr class="border-b"><td class="p-2">${child.key}</td><td class="p-2">${data.lot_total}</td><td class="p-2">${data.profit_loss}</td><td class="p-2">${data.last_update || '-'}</td></tr>`;
    });
    document.getElementById('summaryTable').innerHTML = tableRows;
    // Alerts
    const alertSnap = await db.ref(`alerts/${account}`).limitToLast(5).once('value');
    let alertsHtml = '';
    alertSnap.forEach((alert) => {
      const a = alert.val();
      alertsHtml += `<div class="border-l-4 ${a.type === 'error' ? 'border-red-500' : 'border-yellow-500'} bg-gray-50 p-2 mb-2"><p>${a.message}</p><p class="text-xs text-gray-400">${formatTimestamp(a.timestamp)}</p></div>`;
    });
    document.getElementById('alertsList').innerHTML = alertsHtml || 'Tidak ada alert';
  });
}