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
    
    // Overview cards (responsive grid)
    let html = `
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 mb-6">
        <div class="bg-gray-50 p-3 rounded"><strong>Akun:</strong> ${account}</div>
        <div class="bg-gray-50 p-3 rounded"><strong>Status:</strong> <span class="px-2 py-1 rounded-full text-xs ${license.status === 'ACTIVE' ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'}">${license.status}</span></div>
        <div class="bg-gray-50 p-3 rounded"><strong>Membership:</strong> ${license.membership_type}</div>
        <div class="bg-gray-50 p-3 rounded"><strong>Expiry:</strong> ${formatTimestamp(license.expiry_date)}</div>
        <div class="bg-gray-50 p-3 rounded"><strong>Heartbeat:</strong> ${formatTimestamp(license.last_heartbeat)}</div>
        <div class="bg-gray-50 p-3 rounded"><strong>VPS:</strong> ${license.vps_rental ? `Aktif (sisa $${license.vps_remaining})` : 'Tidak'}</div>
      </div>
      <h3 class="font-bold text-lg mt-4 mb-2">Daily Summary (7 hari terakhir)</h3>
      <div id="summaryContainer" class="overflow-x-auto"></div>
      <h3 class="font-bold text-lg mt-6 mb-2">Alert Terbaru</h3>
      <div id="alertsList" class="space-y-2"></div>
    `;
    document.getElementById('accountDetails').innerHTML = html;
    
    // Load summary
    const summarySnap = await db.ref(`licenses/${account}/daily_summary`).orderByKey().limitToLast(7).once('value');
    let tableRows = '';
    summarySnap.forEach((child) => {
      const data = child.val();
      tableRows += `<tr class="border-b"><td class="p-2 whitespace-nowrap">${child.key}</td><td class="p-2">${data.lot_total}</td><td class="p-2">${data.profit_loss}</td><td class="p-2">${data.last_update || '-'}</td></tr>`;
    });
    document.getElementById('summaryContainer').innerHTML = `
      <table class="min-w-[500px] w-full text-sm border">
        <thead class="bg-gray-100"><tr><th class="p-2">Tanggal</th><th class="p-2">Lot</th><th class="p-2">Profit/Loss</th><th class="p-2">Update</th></tr></thead>
        <tbody>${tableRows || '<tr><td colspan="4" class="p-2 text-center">Belum ada data</td></tr>'}</tbody>
      </table>
    `;
    
    // Load alerts
    const alertSnap = await db.ref(`alerts/${account}`).limitToLast(5).once('value');
    let alertsHtml = '';
    alertSnap.forEach((alert) => {
      const a = alert.val();
      alertsHtml += `<div class="border-l-4 ${a.type === 'error' ? 'border-red-500' : 'border-yellow-500'} bg-gray-50 p-2 rounded"><p>${a.message}</p><p class="text-xs text-gray-400">${formatTimestamp(a.timestamp)}</p></div>`;
    });
    document.getElementById('alertsList').innerHTML = alertsHtml || 'Tidak ada alert';
  });
}
