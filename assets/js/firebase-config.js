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

// Inisialisasi Firebase (menggunakan compat SDK)
firebase.initializeApp(firebaseConfig);
const database = firebase.database();

// Admin auth sederhana (email check)
function isAdmin() {
  const user = firebase.auth().currentUser;
  return user && user.email === "kiroix@gmail.com";
}

// Redirect jika bukan admin
async function requireAdmin() {
  await firebase.auth().onAuthStateChanged(user => {
    if (!user || user.email !== "kiroix@gmail.com") {
      alert("Akses ditolak. Hanya admin yang diizinkan.");
      window.location.href = "/";
    }
  });
}