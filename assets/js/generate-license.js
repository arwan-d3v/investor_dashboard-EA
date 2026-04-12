// WARNING: Secret sebaiknya disimpan di environment variable Netlify.
// Untuk demo, secret di-hardcode. Ganti dengan milikmu.
const SECRET = "YOUR_VERY_SECRET_SALT";

async function generateHMAC(seed) {
  const encoder = new TextEncoder();
  const keyData = encoder.encode(SECRET);
  const messageData = encoder.encode(seed);
  const cryptoKey = await crypto.subtle.importKey(
    "raw", keyData, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", cryptoKey, messageData);
  const hashArray = Array.from(new Uint8Array(signature));
  const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  return hashHex.substring(0, 16).toUpperCase();
}

async function generateLicense(accountNumber, brokerServer, subscriptionType, isIB, vpsRental) {
  const timestamp = Date.now();
  const seed = `KRX|${accountNumber}|${brokerServer}|${subscriptionType}|${timestamp}`;
  const hash = await generateHMAC(seed);
  const part1 = hash.substring(0,4);
  const part2 = hash.substring(4,8);
  const part3 = hash.substring(8,12);
  const licenseKey = `KRX-${part1}-${part2}-${part3}`;
  return { licenseKey, timestamp };
}

async function saveLicense(accountNumber, licenseData) {
  const db = firebase.database();
  const licenseRef = db.ref(`licenses/${accountNumber}`);
  await licenseRef.set(licenseData);
  if (licenseData.membership_type === 'TRIAL') {
    await db.ref(`trial_used_accounts/${accountNumber}`).set(true);
  }
}

// Fungsi baru untuk menyimpan history
async function saveLicenseHistory(accountNumber, licenseData, investorData) {
  const db = firebase.database();
  const historyRef = db.ref('license_history_list').push(); // auto-generate ID
  const historyItem = {
    account_number: accountNumber,
    license_key: licenseData.license_key,
    membership_type: licenseData.membership_type,
    is_ib: licenseData.is_ib,
    price_paid: licenseData.price_paid,
    broker_server: licenseData.broker_server,
    generated_at: licenseData.generated_at,
    expiry_date: licenseData.expiry_date,
    status: licenseData.status,
    vps_rental: licenseData.vps_rental,
    investor_name: investorData.name,
    investor_email: investorData.email,
    investor_telegram: investorData.telegram
  };
  await historyRef.set(historyItem);
}