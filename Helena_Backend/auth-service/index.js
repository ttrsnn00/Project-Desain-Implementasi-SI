const express = require('express');
const mysql = require('mysql2');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');

const app = express();
const PORT = 4001;
const JWT_SECRET = 'rahasia_super_helena_finance_2026';

app.use(express.json());

const db = mysql.createConnection({
    host: 'kampus-db',
    user: 'root',
    password: 'rahasia_db_password',
    database: 'db_pocket_money'
});

db.connect(err => {
    if (err) {
        console.error('❌ Gagal koneksi ke MySQL:', err.message);
        return;
    }
    console.log('🚀 Terhubung ke MySQL Kampus DB (Auth Service)!');
    
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
                const hashedPassword = await bcrypt.hash('admin123', 10);
                const insertAdmin = `
                    INSERT INTO users (nim, password, nama, role) 
                    VALUES ('admin', '${hashedPassword}', 'Administrator Kampus', 'admin')
                `;
                db.query(insertAdmin, () => console.log('👑 Akun Admin (NIM: admin) berhasil dibuat!'));
            }
        });
    });
});

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

app.listen(PORT, '0.0.0.0', () => {
    console.log(`🔑 Auth Service menyala di port ${PORT}`);
});