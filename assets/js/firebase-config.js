// Konfigurasi Firebase dari project "kiroi-x-ecosystem"
const firebaseConfig = {
  apiKey: "AIzaSyAs_1Y_8d5mKhhnmeeNPlsFn4eDsd18E7k",
  authDomain: "kiroi-x-ecosystem.firebaseapp.com",
  databaseURL: "https://kiroi-x-ecosystem-default-rtdb.asia-southeast1.firebasedatabase.app",
  projectId: "kiroi-x-ecosystem",
  storageBucket: "kiroi-x-ecosystem.firebasestorage.app",
  messagingSenderId: "969313803710",
  appId: "1:969313803710:web:5e8b74e3f01e682967adef",
  measurementId: "G-GK269RNX4Y"
};

// Inisialisasi Firebase (Cek agar tidak inisialisasi ganda)
if (!firebase.apps.length) {
    firebase.initializeApp(firebaseConfig);
}

// DEFINISI VARIABEL GLOBAL
// Menggunakan 'window' agar variabel dipastikan terbaca oleh script lain (app.js)
window.database = firebase.database();
window.db = firebase.database(); // ALIAS: Agar error 'db is not defined' hilang

// Helper Fungsi Admin
function isAdmin() {
  const user = firebase.auth().currentUser;
  return user && user.email === "kiroix@gmail.com";
}

async function requireAdmin() {
  return new Promise((resolve) => {
    firebase.auth().onAuthStateChanged(user => {
      // Investor tidak perlu melewati fungsi ini, fungsi ini hanya untuk halaman /admin
      if (!user || user.email !== "kiroix@gmail.com") {
        window.location.href = "/login.html";
      } else {
        resolve();
      }
    });
  });
}
