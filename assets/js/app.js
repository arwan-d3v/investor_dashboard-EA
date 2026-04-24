const mNames = ["Januari","Februari","Maret","April","Mei","Juni","Juli","Agustus","September","Oktober","November","Desember"];
let chartInstance = null;

// --- Init UI ---
const mSel = document.getElementById('monthSel');
const ySel = document.getElementById('yearSel');
const now = new Date();

mNames.forEach((m, i) => mSel.innerHTML += `<option value="${i}" ${i==now.getMonth()?'selected':''}>${m}</option>`);
for(let y=2024; y<=2026; y++) ySel.innerHTML += `<option value="${y}" ${y==now.getFullYear()?'selected':''}>${y}</option>`;

// --- Main Function ---
document.getElementById('btnLoad').onclick = async () => {
    const acc = document.getElementById('accInput').value.trim();
    if(!acc) return;

    toggleLoading(true);

    try {
        const metaSnap = await db.ref(`account_data/${acc}/metadata`).once('value');
        const snap = await db.ref(`account_data/${acc}/snapshots`).once('value');
        
        const meta = metaSnap.val();
        const snapshots = snap.val();

        if(!snapshots) throw new Error("Data Kosong");

        updateSummary(meta, snapshots);
        renderVisuals(snapshots);

    } catch (e) {
        console.error(e);
        alert(e.message);
    } finally {
        toggleLoading(false);
    }
};

function updateSummary(meta, snapshots) {
    const sortedKeys = Object.keys(snapshots).sort((a,b) => parseInt(a) - parseInt(b));
    const latest = snapshots[sortedKeys[sortedKeys.length - 1]];
    const initial = meta?.initial_deposit || 0;

    // Hitung Max Drawdown secara real-time
    let maxEq = 0, maxDD = 0;
    sortedKeys.forEach(k => {
        const eq = snapshots[k].equity;
        if(eq > maxEq) maxEq = eq;
        let dd = ((maxEq - eq) / maxEq) * 100;
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

    Object.keys(snapshots).sort().forEach(ts => {
        const s = snapshots[ts];
        const d = new Date(parseInt(ts));
        if(d.getMonth() === month && d.getFullYear() === year) {
            dailyMap.set(d.getDate(), s);
        }
        cLabels.push(d.getDate() + "/" + (d.getMonth()+1));
        cData.push(s.equity);
    });

    drawChart(cLabels, cData);
    drawCalendar(year, month, dailyMap);
}

function drawCalendar(year, month, dailyMap) {
    const grid = document.getElementById('calGrid');
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
        if(growth > 0.01) style = growth > 1.5 ? "bg-win-heavy" : "bg-win-light";
        else if(growth < -0.01) style = growth < -1.5 ? "bg-loss-heavy" : "bg-loss-light";

        grid.innerHTML += `
            <div class="calendar-day ${style}">
                <span class="text-[9px] font-black opacity-30">${d}</span>
                <div class="text-center">
                    <span class="text-sm font-black block">${data ? growth.toFixed(2)+'%' : '-'}</span>
                    <div class="mt-1 flex flex-col leading-none">
                        <span class="text-[9px] font-bold opacity-80">${profit != 0 ? '$'+profit.toFixed(0) : ''}</span>
                        <span class="text-[7px] font-black uppercase opacity-60">${lots > 0 ? lots.toFixed(2)+' L' : ''}</span>
                    </div>
                </div>
                <div></div>
            </div>`;
    }
}

function drawChart(labels, data) {
    const ctx = document.getElementById('equityChart');
    if(chartInstance) chartInstance.destroy();
    chartInstance = new Chart(ctx, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [{
                data: data,
                borderColor: '#3b82f6',
                borderWidth: 3,
                fill: true,
                tension: 0.4,
                pointRadius: 0,
                backgroundColor: (c) => {
                    const g = c.chart.ctx.createLinearGradient(0, 0, 0, 200);
                    g.addColorStop(0, 'rgba(59, 130, 246, 0.2)');
                    g.addColorStop(1, 'rgba(59, 130, 246, 0)');
                    return g;
                }
            }]
        },
        options: { responsive: true, maintainAspectRatio: false, plugins: { legend: false }, scales: { x: { display: false }, y: { ticks: { font: { size: 9 } } } } }
    });
}

function toggleLoading(s) {
    document.getElementById('btnLoader').classList.toggle('hidden', !s);
    document.getElementById('btnText').innerText = s ? "Processing..." : "Update Dashboard";
}
