require('dotenv').config();
const express = require('express');
const mysql = require('mysql2');

const app = express();
const PORT = process.env.PORT || 4002;

app.use(express.json());

// Koneksi ke Database khusus Billing (terpisah dari service lain)
// Pakai connection POOL supaya otomatis reconnect, bukan mati permanen
// kalau MySQL belum benar-benar siap saat service ini pertama kali start.
const db = mysql.createPool({
    host: process.env.DB_HOST || 'kampus-db',
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME || 'db_billing',
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0
});

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
        console.log('🚀 Terhubung ke MySQL Kampus DB!');
        initTable();
    });
}

function initTable() {
    // 1. Buat Tabel Tagihan
    const createTable = `
        CREATE TABLE IF NOT EXISTS tagihan (
            nim VARCHAR(20) PRIMARY KEY,
            ukt_total INT NOT NULL,
            ukt_dibayar INT NOT NULL,
            status VARCHAR(20) NOT NULL
        )
    `;
    db.query(createTable, (err) => {
        if (err) console.error('Gagal membuat tabel tagihan:', err.message);
        
        // 2. Database Seeding (Suntik data awal jika tabel kosong)
        db.query("SELECT COUNT(*) AS count FROM tagihan", (err, results) => {
            if (err) return console.error(err.message);

            if (results[0].count === 0) {
                const insertData = `
                    INSERT INTO tagihan (nim, ukt_total, ukt_dibayar, status) 
                    VALUES 
                    ('123456', 5000000, 5000000, 'Lunas'),
                    ('654321', 7500000, 2500000, 'Belum Lunas')
                `;
                db.query(insertData, (err) => {
                    if (err) console.error(err.message);
                    else console.log('✅ Data Tagihan awal berhasil disuntikkan!');
                });
            }
        });
    });
}

connectWithRetry();

// --- MIDDLEWARE OTORISASI ---
// Identitas user diteruskan oleh API Gateway via header (sudah diverifikasi JWT di sana).
// Mahasiswa hanya boleh akses data miliknya sendiri; admin boleh akses semua.
const authorizeOwnerOrAdmin = (req, res, next) => {
    const requesterNim = req.headers['x-user-nim'];
    const requesterRole = req.headers['x-user-role'];
    const targetNim = req.params.nim;

    if (requesterRole === 'admin' || requesterNim === targetNim) {
        return next();
    }
    return res.status(403).json({
        status: 'error',
        message: 'Anda tidak memiliki akses ke data mahasiswa lain.',
        data: null
    });
};

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

// Endpoint GET Data Tagihan dari MySQL
app.get('/tagihan/:nim', authorizeOwnerOrAdmin, (req, res) => {
    const studentNim = req.params.nim;
    
    db.query('SELECT * FROM tagihan WHERE nim = ?', [studentNim], (err, results) => {
        // STANDAR JSON: Gagal (Error Sistem)
        if (err) {
            return res.status(500).json({ 
                status: 'error', 
                message: 'Gagal mengambil data tagihan.',
                data: null
            });
        }
        
        if (results.length > 0) {
            // STANDAR JSON: Sukses
            res.status(200).json({ 
                status: 'success', 
                message: 'Data tagihan berhasil diambil.',
                data: results[0] 
            });
        } else {
            // STANDAR JSON: Gagal (Data tidak ditemukan)
            res.status(404).json({ 
                status: 'error', 
                message: 'Data tagihan tidak ditemukan.',
                data: null 
            });
        }
    });
});

// --- ENDPOINT BARU KHUSUS ADMIN: MENERBITKAN TAGIHAN UKT ---
app.post('/tagihan', requireAdmin, (req, res) => {
    const { nim, ukt_total } = req.body;

    if (!nim || !ukt_total) {
        return res.status(400).json({ status: 'error', message: 'NIM dan Total UKT wajib diisi!', data: null });
    }

    // Menggunakan INSERT ... ON DUPLICATE KEY UPDATE 
    // Artinya: Jika belum ada, buatkan baru. Jika sudah ada, perbarui nominalnya.
    const insertQuery = `
        INSERT INTO tagihan (nim, ukt_total, ukt_dibayar, status) 
        VALUES (?, ?, 0, 'Belum Lunas') 
        ON DUPLICATE KEY UPDATE ukt_total = ?, status = 'Belum Lunas'
    `;

    db.query(insertQuery, [nim, ukt_total, ukt_total], (err, result) => {
        if (err) {
            console.error(err);
            return res.status(500).json({ status: 'error', message: 'Gagal menerbitkan tagihan.', data: null });
        }
        res.status(201).json({ 
            status: 'success', 
            message: `Tagihan UKT sebesar Rp ${ukt_total} untuk NIM ${nim} berhasil diterbitkan!`, 
            data: null 
        });
    });
});

// --- ENDPOINT PEMBAYARAN UKT (MAHASISWA) ---
app.put('/tagihan/:nim/bayar', authorizeOwnerOrAdmin, (req, res) => {
    const nim = req.params.nim;
    
    // Query ini akan mengubah ukt_dibayar menjadi sama dengan ukt_total, dan status jadi Lunas
    const updateQuery = `
        UPDATE tagihan 
        SET ukt_dibayar = ukt_total, status = 'Lunas' 
        WHERE nim = ? AND status != 'Lunas'
    `;
    
    db.query(updateQuery, [nim], (err, result) => {
        if (err) {
            console.error(err);
            return res.status(500).json({ status: 'error', message: 'Gagal memproses pembayaran.', data: null });
        }
        
        // Jika tidak ada baris yang berubah, berarti tagihan sudah lunas atau NIM tidak ada
        if (result.affectedRows === 0) {
            return res.status(400).json({ status: 'error', message: 'Tagihan sudah lunas atau tidak ditemukan.', data: null });
        }

        res.status(200).json({ status: 'success', message: 'Pembayaran UKT berhasil diproses!', data: null });
    });
});

// --- ENDPOINT ROLLBACK PEMBAYARAN UKT ---
// Dipanggil dari frontend ketika pencatatan transaksi pengeluaran GAGAL
// setelah tagihan sudah terlanjur ditandai lunas (lihat keuangan_provider.dart
// fungsi bayarUKTReal -> _rollbackPembayaranUKT). Tanpa endpoint ini, tagihan
// bisa tercatat lunas padahal tidak ada transaksi pengeluaran yang menyertainya.
app.put('/tagihan/:nim/batal-bayar', authorizeOwnerOrAdmin, (req, res) => {
    const nim = req.params.nim;

    const rollbackQuery = `
        UPDATE tagihan 
        SET ukt_dibayar = 0, status = 'Belum Lunas' 
        WHERE nim = ? AND status = 'Lunas'
    `;

    db.query(rollbackQuery, [nim], (err, result) => {
        if (err) {
            console.error('Gagal rollback pembayaran UKT:', err);
            return res.status(500).json({ status: 'error', message: 'Gagal membatalkan pembayaran.', data: null });
        }

        if (result.affectedRows === 0) {
            return res.status(400).json({ status: 'error', message: 'Tidak ada tagihan lunas yang bisa dibatalkan untuk NIM ini.', data: null });
        }

        res.status(200).json({ status: 'success', message: 'Pembayaran UKT berhasil dibatalkan (rollback).', data: null });
    });
});

// Ditambahkan '0.0.0.0' agar aman untuk jaringan Docker
app.listen(PORT, '0.0.0.0', () => {
    console.log(`💰 Campus Billing Service aktif di port ${PORT}`);
});