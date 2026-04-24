const mNames = ["Januari","Februari","Maret","April","Mei","Juni","Juli","Agustus","September","Oktober","November","Desember"];
let chartInstance = null;
let currentSnapshots = null; // Simpan cache data agar saat ganti bulan tidak perlu fetch ulang

// --- Init UI ---
const mSel = document.getElementById('monthSel');
const ySel = document.getElementById('yearSel');
const now = new Date();

mNames.forEach((m, i) => mSel.innerHTML += `<option value="${i}" ${i==now.getMonth()?'selected':''}>${m}</option>`);
for(let y=2024; y<=2026; y++) ySel.innerHTML += `<option value="${y}" ${y==now.getFullYear()?'selected':''}>${y}</option>`;

// --- Event Listener untuk Ganti Bulan/Tahun Tanpa Login Ulang ---
const reRender = () => { if(currentSnapshots) renderVisuals(currentSnapshots); };
mSel.onchange = reRender;
ySel.onchange = reRender;

// --- Main Function: Login & Fetch ---
document.getElementById('btnLoad').onclick = async () => {
    const acc = document.getElementById('accInput').value.trim();
    if(!acc) return alert("Masukkan nomor akun!");

    toggleLoading(true);

    try {
        const metaSnap = await db.ref(`account_data/${acc}/metadata`).once('value');
        const snapshotsSnap = await db.ref(`account_data/${acc}/snapshots`).once('value');

        if(!snapshotsSnap.exists()) {
            throw new Error("Akun tidak ditemukan atau belum ada data.");
        }

        currentSnapshots = snapshotsSnap.val(); // Simpan ke cache

        updateSummary(metaSnap.val(), currentSnapshots);
        renderVisuals(currentSnapshots);

        // TRANSISI KE DASHBOARD
        document.getElementById('displayAcc').innerText = "Account #" + acc;
        document.getElementById('loginScreen').classList.add('hidden');
        document.getElementById('dashboardView').classList.remove('hidden');
        setTimeout(() => {
            document.getElementById('dashboardView').classList.add('opacity-100');
        }, 100);

    } catch (e) {
        alert(e.message);
    } finally {
        toggleLoading(false);
    }
};

// Logika untuk Login Admin
document.getElementById('btnAdmin').onclick = () => {
    const pin = document.getElementById('adminPin').value.trim();
    if (!pin) return alert("Silakan masukkan PIN Admin.");

    if (pin === "692139") {
        document.getElementById('btnAdmin').innerText = "Authenticating...";
        setTimeout(() => {
            window.location.href = "https://krx-dashboard.arwan-d3v.workers.dev/admin";
        }, 800);
    } else {
        alert("Akses Ditolak: PIN Tidak Valid!");
        document.getElementById('adminPin').value = "";
    }
};

function toggleLoading(s) {
    const loader = document.getElementById('btnLoader');
    const text = document.getElementById('btnText');
    if(loader) loader.classList.toggle('hidden', !s);
    if(text) text.innerText = s ? "Mencari Data..." : "Masuk ke Dashboard";
}

window.onload = () => {
    const params = new URLSearchParams(window.location.search);
    const accParam = params.get('acc');
    if(accParam) {
        document.getElementById('accInput').value = accParam;
        document.getElementById('btnLoad').click();
    }
};

function updateSummary(meta, snapshots) {
    const sortedKeys = Object.keys(snapshots).sort((a,b) => parseInt(a) - parseInt(b));
    const latest = snapshots[sortedKeys[sortedKeys.length - 1]];
    const initial = meta?.initial_deposit || 1; // Cegah pembagian dengan nol

    let maxEq = 0, maxDD = 0;
    sortedKeys.forEach(k => {
        const eq = snapshots[k].equity;
        if(eq > maxEq) maxEq = eq;
        let dd = maxEq > 0 ? ((maxEq - eq) / maxEq) * 100 : 0;
        if(dd > maxDD) maxDD = dd;
    });

    document.getElementById('statDeposit').innerText = `$${initial.toLocaleString()}`;
    document.getElementById('statEquity').innerText = `$${latest.equity.toLocaleString()}`;
    document.getElementById('statGrowth').innerText = `${((latest.equity - initial)/initial*100).toFixed(2)}%`;
    document.getElementById('statDD').innerText = `${maxDD.toFixed(2)}%`;
    document.getElementById('brokerName').innerText = meta?.broker || "MT5 Server";
}

function renderVisuals(snapshots) {
    const month = parseInt(mSel.value);
    const year = parseInt(ySel.value);
    const dailyMap = new Map();
    const cLabels = [], cData = [];

    const sortedKeys = Object.keys(snapshots).sort((a,b) => parseInt(a) - parseInt(b));
    
    sortedKeys.forEach(ts => {
        const s = snapshots[ts];
        const d = new Date(parseInt(ts));
        
        // Data untuk Chart (Semua data agar curve terlihat panjang)
        cLabels.push(d.getDate() + "/" + (d.getMonth()+1));
        cData.push(s.equity);

        // Data untuk Kalender (Hanya bulan & tahun terpilih)
        if(d.getMonth() === month && d.getFullYear() === year) {
            dailyMap.set(d.getDate(), s);
        }
    });

    drawChart(cLabels, cData);
    drawCalendar(year, month, dailyMap);
}

function drawCalendar(year, month, dailyMap) {
    const grid = document.getElementById('calGrid');
    if(!grid) return;
    grid.innerHTML = '';
    
    const firstDay = new Date(year, month, 1).getDay();
    const daysInMonth = new Date(year, month + 1, 0).getDate();

    for(let i=0; i<firstDay; i++) grid.innerHTML += `<div class="bg-transparent opacity-0"></div>`;

    for(let d=1; d<=daysInMonth; d++) {
        const data = dailyMap.get(d);
        const growth = data ? parseFloat(data.daily_growth_percent || 0) : 0;
        const profit = data ? parseFloat(data.daily_profit || 0) : 0;
        const lots = data ? parseFloat(data.daily_lots || 0) : 0;

        let style = "bg-neutral";
        if(growth > 0.01) style = growth > 1.5 ? "bg-win-heavy text-white" : "bg-win-light";
        else if(growth < -0.01) style = growth < -1.5 ? "bg-loss-heavy text-white" : "bg-loss-light";

        grid.innerHTML += `
            <div class="calendar-day ${style} p-2 rounded-xl flex flex-col justify-between border border-slate-50 min-h-[90px]">
                <span class="text-[9px] font-black opacity-30">${d}</span>
                <div class="text-center">
                    <span class="text-sm font-black block">${data ? growth.toFixed(2)+'%' : '-'}</span>
                    <div class="mt-1 flex flex-col leading-none">
                        <span class="text-[9px] font-bold opacity-80">${data && profit !== 0 ? '$'+profit.toFixed(0) : ''}</span>
                        <span class="text-[7px] font-black uppercase opacity-60">${data && lots > 0 ? lots.toFixed(2)+' L' : ''}</span>
                    </div>
                </div>
                <div></div>
            </div>`;
    }
}

function drawChart(labels, data) {
    const ctx = document.getElementById('equityChart');
    if(!ctx) return;
    if(chartInstance) chartInstance.destroy();
    chartInstance = new Chart(ctx, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [{
                data: data,
                borderColor: '#3b82f6',
                borderWidth: 2,
                fill: true,
                tension: 0.4,
                pointRadius: 0,
                backgroundColor: (c) => {
                    const chart = c.chart;
                    const {ctx, chartArea} = chart;
                    if (!chartArea) return null;
                    const gradient = ctx.createLinearGradient(0, chartArea.bottom, 0, chartArea.top);
                    gradient.addColorStop(0, 'rgba(59, 130, 246, 0)');
                    gradient.addColorStop(1, 'rgba(59, 130, 246, 0.2)');
                    return gradient;
                }
            }]
        },
        options: { 
            responsive: true, 
            maintainAspectRatio: false, 
            plugins: { legend: false }, 
            scales: { 
                x: { display: false }, 
                y: { ticks: { font: { size: 9 }, callback: (v) => '$' + v.toLocaleString() } } 
            } 
        }
    });
}
