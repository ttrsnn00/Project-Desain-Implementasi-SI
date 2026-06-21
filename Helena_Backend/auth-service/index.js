require('dotenv').config();
const express = require('express');
const mysql = require('mysql2');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');

const app = express();
const PORT = process.env.PORT || 4001;
const JWT_SECRET = process.env.JWT_SECRET;

if (!JWT_SECRET) {
    console.error('❌ JWT_SECRET tidak ditemukan di environment variables. Cek file .env!');
    process.exit(1);
}

app.use(express.json());

// Pakai connection POOL (bukan createConnection tunggal) supaya otomatis
// reconnect kalau koneksi pertama gagal/putus -- mencegah service "mati permanen"
// kalau MySQL belum benar-benar siap saat service ini pertama kali start.
const db = mysql.createPool({
    host: process.env.DB_HOST || 'kampus-db',
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME || 'db_auth',
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0
});

// Tes koneksi awal dengan retry, supaya error di log jelas dan tabel
// langsung dibuat begitu MySQL benar-benar siap (bukan baru saat query pertama masuk).
function connectWithRetry(retriesLeft = 10) {
    db.getConnection((err, connection) => {
        if (err) {
            console.error(`❌ Gagal koneksi ke MySQL (sisa percobaan: ${retriesLeft}):`, err.message);
            if (retriesLeft > 0) {
                setTimeout(() => connectWithRetry(retriesLeft - 1), 3000);
            } else {
                console.error('❌ Menyerah mencoba konek ke MySQL setelah beberapa kali percobaan.');
            }
            return;
        }
        connection.release();
        console.log('🚀 Terhubung ke MySQL Kampus DB (Auth Service)!');
        initTable();
    });
}

function initTable() {
    // PERUBAHAN: Penambahan kolom 'role' dengan default 'mahasiswa'
    const createTable = `
        CREATE TABLE IF NOT EXISTS users (
            nim VARCHAR(20) PRIMARY KEY,
            password VARCHAR(255) NOT NULL, 
            nama VARCHAR(100) NOT NULL,
            role ENUM('mahasiswa', 'admin') DEFAULT 'mahasiswa' 
        )
    `;
    db.query(createTable, async (err) => {
        if (err) console.error('Gagal membuat tabel users:', err.message);
        
        db.query("SELECT COUNT(*) AS count FROM users WHERE role = 'admin'", async (err, results) => {
            // PERUBAHAN: Injeksi akun Admin otomatis jika belum ada
            if (results[0].count === 0) {
                const adminPassword = process.env.ADMIN_DEFAULT_PASSWORD;
                if (!adminPassword) {
                    console.error('❌ ADMIN_DEFAULT_PASSWORD tidak ditemukan di environment variables. Akun admin tidak dibuat otomatis.');
                    return;
                }
                const hashedPassword = await bcrypt.hash(adminPassword, 10);
                const insertAdmin = `
                    INSERT INTO users (nim, password, nama, role) 
                    VALUES (?, ?, 'Administrator Kampus', 'admin')
                `;
                db.query(insertAdmin, ['admin', hashedPassword], () => console.log('👑 Akun Admin (NIM: admin) berhasil dibuat!'));
            }
        });
    });
}

connectWithRetry();

app.post('/register', async (req, res) => {
    const { nim, nama, password } = req.body;
    if (!nim || !nama || !password) return res.status(400).json({ status: 'error', message: 'Semua kolom wajib diisi!', data: null });

    try {
        db.query('SELECT nim FROM users WHERE nim = ?', [nim], async (err, results) => {
            if (err) return res.status(500).json({ status: 'error', message: 'Kesalahan sistem.', data: null });
            if (results.length > 0) return res.status(409).json({ status: 'error', message: 'NIM sudah terdaftar!', data: null });

            const hashedPassword = await bcrypt.hash(password, 10);
            // Pendaftar dari aplikasi selalu menjadi 'mahasiswa' secara otomatis
            const insertQuery = 'INSERT INTO users (nim, password, nama, role) VALUES (?, ?, ?, "mahasiswa")';
            db.query(insertQuery, [nim, hashedPassword, nama], (err, result) => {
                if (err) return res.status(500).json({ status: 'error', message: 'Gagal menyimpan.', data: null });
                res.status(201).json({ status: 'success', message: 'Akun berhasil dibuat!', data: null });
            });
        });
    } catch (error) {
        res.status(500).json({ status: 'error', message: 'Error server.', data: null });
    }
});

app.post('/login', (req, res) => {
    const { nim, password } = req.body;
    db.query('SELECT * FROM users WHERE nim = ?', [nim], async (err, results) => {
        if (err) return res.status(500).json({ status: 'error', message: 'Kesalahan sistem.', data: null });
        
        if (results.length > 0) {
            const user = results[0];
            const match = await bcrypt.compare(password, user.password);
            if (match) {
                // PERUBAHAN: Menyertakan role ke dalam token JWT
                const payload = { nim: user.nim, nama: user.nama, role: user.role };
                const token = jwt.sign(payload, JWT_SECRET, {expiresIn: '2h'});
                res.status(200).json({
                    status: 'success',
                    message: `Selamat datang, ${user.nama}!`,
                    data: { token: token, nama: user.nama, nim: user.nim, role: user.role } 
                });
            } else {
                res.status(401).json({ status: 'error', message: 'Password salah!', data: null });
            }
        } else {
            res.status(404).json({ status: 'error', message: 'NIM tidak ditemukan!', data: null });
        }
    });
});

app.put('/profile', async (req, res) => {
    const { nim, nama, password } = req.body;
    if (!nim || !nama) return res.status(400).json({ status: 'error', message: 'NIM dan Nama tidak boleh kosong!', data: null });

    try {
        if (password && password.trim() !== '') {
            const hashedPassword = await bcrypt.hash(password, 10);
            db.query('UPDATE users SET nama = ?, password = ? WHERE nim = ?', [nama, hashedPassword, nim], (err, result) => {
                if (err) return res.status(500).json({ status: 'error', message: 'Gagal memperbarui profil.', data: null });
                res.status(200).json({ status: 'success', message: 'Profil dan Password diperbarui!', data: null });
            });
        } else {
            db.query('UPDATE users SET nama = ? WHERE nim = ?', [nama, nim], (err, result) => {
                if (err) return res.status(500).json({ status: 'error', message: 'Gagal memperbarui profil.', data: null });
                res.status(200).json({ status: 'success', message: 'Nama profil diperbarui!', data: null });
            });
        }
    } catch (error) {
        res.status(500).json({ status: 'error', message: 'Error server.', data: null });
    }
});

// --- MIDDLEWARE OTORISASI ---
// Sama seperti pola di campus-billing-service & pocket-money-service:
// identitas user diteruskan oleh API Gateway via header (sudah diverifikasi
// JWT di sana). Endpoint ini KHUSUS admin.
const requireAdmin = (req, res, next) => {
    if (req.headers['x-user-role'] !== 'admin') {
        return res.status(403).json({
            status: 'error',
            message: 'Hanya admin yang dapat mengakses endpoint ini.',
            data: null
        });
    }
    next();
};

// --- ENDPOINT KHUSUS ADMIN: DAFTAR SEMUA MAHASISWA ---
// Dipakai admin untuk melihat siapa saja yang sudah daftar, supaya bisa
// tahu mahasiswa mana yang BELUM punya tagihan UKT (dicek silang manual
// dengan data dari campus-billing-service, karena dua data ini ada di
// database terpisah -- lihat catatan di bawah).
app.get('/users', requireAdmin, (req, res) => {
    // Sengaja TIDAK menyertakan kolom password, sekalipun sudah ter-hash --
    // tidak perlu dikirim ke frontend sama sekali.
    db.query(
        "SELECT nim, nama, role FROM users WHERE role = 'mahasiswa' ORDER BY nim",
        (err, results) => {
            if (err) {
                console.error('Gagal mengambil daftar mahasiswa:', err);
                return res.status(500).json({ status: 'error', message: 'Kesalahan sistem.', data: null });
            }
            res.status(200).json({ status: 'success', message: 'Daftar mahasiswa berhasil diambil.', data: results });
        }
    );
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`🔑 Auth Service menyala di port ${PORT}`);
});
